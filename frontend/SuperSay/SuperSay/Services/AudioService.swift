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
    
    // CRITICAL: Robust Completion Tracking
    private var scheduledBufferCount = 0
    
    // Durations
    private var estimatedDuration: TimeInterval = 0
    private var actualDataDuration: TimeInterval = 0
    
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
    
    func setEstimatedDuration(textLength: Int, speed: Double) {
        let rawSeconds = Double(textLength) / 12.0
        self.estimatedDuration = max(1.0, rawSeconds / speed)
        self.duration = self.estimatedDuration
    }
    
    func playChunk(_ data: Data, volume: Float) {
        var dataToProcess = data
        
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
        
        pcmAccumulator.append(dataToProcess)
        let bytesToProcess = (pcmAccumulator.count / 2) * 2
        guard bytesToProcess > 0 else { return }
        
        let chunkToBuffer = pcmAccumulator.prefix(bytesToProcess)
        pcmAccumulator.removeFirst(bytesToProcess)
        lastAudioData.append(chunkToBuffer)
        
        self.actualDataDuration = Double(lastAudioData.count / 2) / 24000.0
        self.duration = max(self.estimatedDuration, self.actualDataDuration)
        
        if !isDragging {
            guard let buffer = dataToBuffer(chunkToBuffer) else { return }
            playerNode.volume = volume
            
            // TRACK SCHEDULED BUFFERS
            self.scheduledBufferCount += 1
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.scheduledBufferCount -= 1
                    // Only check for stop if the stream is totally finished
                    if !self.isStreamActive && self.scheduledBufferCount == 0 && self.isPlaying {
                         print("🎬 AudioService: All scheduled buffers finished. Stopping.")
                         self.stop()
                    }
                }
            })
            
            if !hasStartedPlayback && lastAudioData.count > 4800 { // Increased buffer to 200ms for safety
                startPlayback()
            }
        }
    }
    
    private func startPlayback() {
        guard !hasStartedPlayback else { return }
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
    
    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                let elapsedSinceStart = Date().timeIntervalSince(self.startTime ?? Date())
                self.currentTime = self.pausedTime + elapsedSinceStart
                if !self.isDragging {
                    self.progress = self.duration > 0 ? min(1.0, self.currentTime / self.duration) : 0
                }
            }
    }
    
    func seek(to percentage: Double) {
        guard !lastAudioData.isEmpty else { return }
        playerNode.stop()
        self.scheduledBufferCount = 0 // Clear count
        
        let targetTime = percentage * duration
        let targetSample = Int(targetTime * 24000)
        var targetByte = targetSample * 2
        
        if targetByte >= lastAudioData.count { targetByte = lastAudioData.count - 2 }
        if targetByte < 0 { targetByte = 0 }
        if targetByte % 2 != 0 { targetByte -= 1 }
        
        let remainingData = lastAudioData.advanced(by: targetByte)
        if let buffer = dataToBuffer(remainingData) {
            self.scheduledBufferCount += 1
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduledBufferCount -= 1
                }
            })
            
            let now = Date()
            self.pausedTime = targetTime
            self.startTime = now
            self.currentTime = targetTime
            
            if !engine.isRunning { try? engine.start() }
            playerNode.play()
            isPlaying = true
            startTimer()
        }
    }
    
    func togglePause() {
        if playerNode.isPlaying {
            playerNode.pause()
            engine.pause()
            if let start = startTime {
                pausedTime += Date().timeIntervalSince(start)
            }
            isPlaying = false
        } else {
            try? engine.start()
            playerNode.play()
            startTime = Date()
            isPlaying = true
            startTimer()
        }
    }
    
    func prepareForStream() {
        stop()
        isStreamActive = true
    }
    
    func finishStream() {
        isStreamActive = false
        // Check if we already finished (sometimes stream closes after playback is done)
        if scheduledBufferCount == 0 && isPlaying {
            stop()
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
        estimatedDuration = 0
        actualDataDuration = 0
        duration = 0
        scheduledBufferCount = 0
    }
    
    private func dataToBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count) / 2 // 16-bit
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress, let audioBuffer = buffer.int16ChannelData?[0] {
                let dataPointer = baseAddress.assumingMemoryBound(to: Int16.self)
                for i in 0..<Int(frameCount) { audioBuffer[i] = dataPointer[i] }
            }
        }
        return buffer
    }

    func exportToDesktop() {
        guard !lastAudioData.isEmpty else { return }
        let headerSize = 44
        let totalSize = lastAudioData.count + headerSize - 8
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(totalSize)) { Data($0) })
        header.append("WAVEfmt ".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(24000)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(24000 * 2)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(2)) { Data($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(16)) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(lastAudioData.count)) { Data($0) })
        
        let wavData = header + lastAudioData
        let filename = "SuperSay_\(Int(Date().timeIntervalSince1970)).wav"
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
        try? wavData.write(to: desktopURL)
    }
}
