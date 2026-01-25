import AVFoundation
import Combine
import UserNotifications
import AppKit

@MainActor
class AudioService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isDragging = false
    
    // Audio Engine
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!
    
    private var timer: AnyCancellable?
    private var lastAudioData = Data()
    private var startTime: Date?
    private var pausedTime: TimeInterval = 0
    
    // Streaming state
    private var headerAccumulator = Data()
    private var hasStrippedHeader = false
    private var isStreamActive = false
    private var pcmAccumulator = Data()
    private var hasStartedPlayback = false
    
    // New: Handle manual duration estimation
    private var estimatedDuration: TimeInterval = 1.0
    
    override init() {
        super.init()
        setupEngine()
    }
    
    private func setupEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            print("❌ AudioService: Engine start error: \(error)")
        }
    }
    
    // Called by ViewModel BEFORE streaming starts
    func setEstimatedDuration(textLength: Int, speed: Double) {
        // Avg reading speed: ~15 chars per second.
        let rawSeconds = Double(textLength) / 15.0
        self.estimatedDuration = max(1.0, rawSeconds / speed)
        self.duration = self.estimatedDuration
        print("⏱️ AudioService: Estimated duration set to \(self.duration)s")
    }
    
    func playChunk(_ data: Data, volume: Float) {
        var dataToProcess = data
        
        // 1. Header Stripping
        if !hasStrippedHeader {
            headerAccumulator.append(dataToProcess)
            if headerAccumulator.count >= 44 {
                dataToProcess = headerAccumulator.advanced(by: 44)
                hasStrippedHeader = true
                headerAccumulator = Data()
            } else {
                return
            }
        }
        
        // 2. Data Alignment
        pcmAccumulator.append(dataToProcess)
        let bytesToProcess = (pcmAccumulator.count / 2) * 2
        guard bytesToProcess > 0 else { return }
        
        let chunkToBuffer = pcmAccumulator.prefix(bytesToProcess)
        pcmAccumulator.removeFirst(bytesToProcess)
        
        // Append to our history
        lastAudioData.append(chunkToBuffer)
        
        // Calculate actual duration based on data received so far
        let actualDuration = TimeInterval(lastAudioData.count / 2) / 24000.0
        
        // Update duration: Use estimate until actual data surpasses it (prevents slider jumping back)
        if actualDuration > self.estimatedDuration {
            self.duration = actualDuration
        }
        
        // 3. Convert & Play
        // Only schedule if we aren't currently dragging/seeking, otherwise we interrupt the seek logic
        if !isDragging {
            guard let buffer = dataToBuffer(chunkToBuffer) else { return }
            playerNode.volume = volume
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            
            if !hasStartedPlayback && lastAudioData.count > 4800 {
                startPlayback()
            }
        }
    }
    
    // Added to support multiple segments in one stream
    func prepareForNextSentence() {
        hasStrippedHeader = false
        headerAccumulator = Data()
        pcmAccumulator = Data()
    }
    
    private func startPlayback() {
        do {
            if !engine.isRunning { try engine.start() }
            playerNode.play()
            isPlaying = true
            hasStartedPlayback = true
            startTime = Date()
            startTimer()
        } catch {
            print("❌ AudioService: Start error: \(error)")
        }
    }
    
    func seek(to percentage: Double) {
        guard !lastAudioData.isEmpty else { return }
        
        // 1. Stop current playback to clear queue
        playerNode.stop()
        
        // 2. Calculate byte offset (must be even for 16-bit PCM)
        let targetTime = percentage * duration
        let targetSample = Int(targetTime * 24000)
        var targetByte = targetSample * 2
        
        // Clamp
        if targetByte >= lastAudioData.count { targetByte = lastAudioData.count - 2 }
        if targetByte < 0 { targetByte = 0 }
        
        // Ensure even alignment
        if targetByte % 2 != 0 { targetByte -= 1 }
        
        print("⏩ AudioService: Seeking to \(String(format: "%.1f", targetTime))s (Byte \(targetByte)/\(lastAudioData.count))")
        
        // 3. Create buffer from History[offset...]
        let remainingData = lastAudioData.advanced(by: targetByte)
        
        if let buffer = dataToBuffer(remainingData) {
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            
            // 4. Update Time State
            // We adjust startTime so the timer calculation (Date() - startTime) results in the new Seek Time
            let now = Date()
            self.pausedTime = targetTime // Reset accumulation
            self.startTime = now // Reset anchor
            self.currentTime = targetTime
            
            if !engine.isRunning { try? engine.start() }
            playerNode.play()
            isPlaying = true
            startTimer()
        }
    }
    
    @MainActor
    func togglePause() {
        if playerNode.isPlaying {
            playerNode.pause()
            engine.pause()
            // Snapshot the time elapsed so far
            if let start = startTime {
                pausedTime += Date().timeIntervalSince(start)
            }
            isPlaying = false
        } else {
            try? engine.start()
            playerNode.play()
            // Reset anchor to now
            startTime = Date()
            isPlaying = true
            startTimer()
        }
    }
    
    func stop() {
        playerNode.stop()
        timer?.cancel()
        isPlaying = false
        progress = 0
        currentTime = 0
        pausedTime = 0
        startTime = nil
        lastAudioData = Data()
        hasStrippedHeader = false
        isStreamActive = false
        pcmAccumulator = Data()
        hasStartedPlayback = false
        headerAccumulator = Data()
        estimatedDuration = 1.0
        duration = 0 // Reset duration
    }
    
    func prepareForStream() {
        stop()
        isStreamActive = true
    }
    
    func finishStream() {
        isStreamActive = false
    }
    
    func reset() {
        stop()
    }
    
    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                
                // If streaming, current time is derived from (PausedAccumulation + (Now - LastStart))
                let elapsedSinceResume = Date().timeIntervalSince(self.startTime ?? Date())
                self.currentTime = self.pausedTime + elapsedSinceResume
                
                if !self.isDragging {
                    self.progress = self.duration > 0 ? self.currentTime / self.duration : 0
                }
                
                // Auto-stop if we reached the end of KNOWN data and stream is done
                if !self.isStreamActive && self.currentTime >= self.duration + 0.1 {
                    // Only stop if we really are at the end of the buffer
                    // (Simple heuristic: check if progress is near 1.0)
                    if self.progress >= 0.99 {
                        self.stop()
                    }
                }
            }
    }
    
    func exportToDesktop() {
        guard !lastAudioData.isEmpty else { return }
        
        // Re-construct a proper WAV for export
        let wavData = createWavData(from: lastAudioData)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SuperSay_\(formatter.string(from: Date())).wav"
        
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let fileURL = desktopURL.appendingPathComponent(filename)
        
        do {
            try wavData.write(to: fileURL)
            showNotification(title: "Export Successful", body: "Saved to Desktop: \(filename)")
            MetricsService.shared.trackExport()
        } catch {
            showNotification(title: "Export Failed", body: error.localizedDescription)
        }
    }
    
    private func dataToBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        
        data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            if let baseAddress = rawBufferPointer.baseAddress,
               let audioBuffer = buffer.int16ChannelData?[0] {
                let dataPointer = baseAddress.assumingMemoryBound(to: Int16.self)
                for i in 0..<Int(frameCount) {
                    audioBuffer[i] = dataPointer[i]
                }
            }
        }
        return buffer
    }
    
    private func createWavData(from pcmData: Data) -> Data {
        let headerSize = 44
        let totalSize = pcmData.count + headerSize - 8
        let dataSize = pcmData.count
        
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(totalSize)) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(24000)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(24000 * 2)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(2)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16)) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize)) { Data($0) })
        
        return header + pcmData
    }
    
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
