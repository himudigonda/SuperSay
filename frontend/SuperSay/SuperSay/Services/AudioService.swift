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
    
    func playChunk(_ data: Data, volume: Float) {
        var dataToProcess = data
        
        // 1. Robust Header Stripping
        if !hasStrippedHeader {
            headerAccumulator.append(dataToProcess)
            if headerAccumulator.count >= 44 {
                // We have the full header, discard it and keep the rest
                dataToProcess = headerAccumulator.advanced(by: 44)
                hasStrippedHeader = true
                headerAccumulator = Data() // Clear
            } else {
                // Still waiting for more header bytes
                return
            }
        }
        
        // 2. Data Alignment (Ensure multiples of 2 bytes for 16-bit PCM)
        pcmAccumulator.append(dataToProcess)
        let bytesToProcess = (pcmAccumulator.count / 2) * 2
        
        guard bytesToProcess > 0 else { return }
        
        let chunkToBuffer = pcmAccumulator.prefix(bytesToProcess)
        pcmAccumulator.removeFirst(bytesToProcess)
        
        lastAudioData.append(chunkToBuffer)
        
        // 3. Convert to Buffer
        guard let buffer = dataToBuffer(chunkToBuffer) else { return }
        
        playerNode.volume = volume
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        
        // 4. Playback Logic with Mini-Buffering
        // We wait for at least 0.1s (4800 bytes) of audio before starting the node
        // to prevent jitter and running the buffer dry immediately.
        if !hasStartedPlayback && lastAudioData.count > 4800 {
            do {
                if !engine.isRunning { try engine.start() }
                playerNode.play()
                isPlaying = true
                hasStartedPlayback = true
                startTime = Date()
                startTimer()
                print("▶️ AudioService: Playback started (Buffered \(lastAudioData.count) bytes)")
            } catch {
                print("❌ AudioService: Failed to start playback engine: \(error)")
            }
        }
        
        // Update duration estimate
        let totalSamples = lastAudioData.count / 2
        self.duration = TimeInterval(totalSamples) / 24000.0
    }
    
    @MainActor // Added @MainActor to togglePause
    func togglePause() {
        if playerNode.isPlaying {
            playerNode.pause()
            engine.pause()
            pausedTime += Date().timeIntervalSince(startTime ?? Date())
            isPlaying = false
        } else {
            do {
                try engine.start()
                playerNode.play()
                startTime = Date()
                isPlaying = true
                startTimer()
            } catch {
                print("❌ AudioService: Resume error: \(error)")
            }
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
    
    func seek(to percentage: Double) {
        // Seeking in a live buffer stream is complex. 
        // For now, we only support stopping/restarting.
        print("⚠️ AudioService: Seek not yet implemented for streaming engine.")
    }
    
    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                
                let elapsedSinceStart = Date().timeIntervalSince(self.startTime ?? Date())
                self.currentTime = self.pausedTime + elapsedSinceStart
                
                if !self.isDragging {
                    self.progress = self.duration > 0 ? self.currentTime / self.duration : 0
                }
                
                // If we've played past the estimated duration (plus buffer), assume finished
                if !self.isStreamActive && self.currentTime >= self.duration + 0.1 {
                    self.stop()
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
