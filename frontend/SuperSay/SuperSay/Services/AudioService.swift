import AVFoundation
import Combine
import AppKit

@MainActor
class AudioService: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isDragging = false
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!
    
    private var lastAudioData = Data()
    private var headerAccumulator = Data()
    private var pcmAccumulator = Data()
    private var hasStrippedHeader = false
    private var isStreamActive = false
    private var hasStartedPlayback = false
    private var scheduledBufferCount = 0
    
    // Timer for progress
    private var timer: AnyCancellable?
    private var pausedTime: TimeInterval = 0
    
    // For duration estimation
    private var estimatedDuration: TimeInterval = 0
    
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
        
        // 1. Strip Header
        if !hasStrippedHeader {
            headerAccumulator.append(dataToProcess)
            if headerAccumulator.count >= 44 {
                dataToProcess = headerAccumulator.suffix(from: 44)
                hasStrippedHeader = true
                headerAccumulator = Data()
                print("🔊 AudioService: Header stripped. PCM accumulation started.")
            } else {
                return 
            }
        }
        
        if dataToProcess.isEmpty { return }
        
        // 2. PCM Accumulation with Alignment Fix
        pcmAccumulator.append(dataToProcess)
        
        // --- FIX: Only process full 2-byte samples ---
        let totalAvailable = pcmAccumulator.count
        let bytesToProcess = (totalAvailable / 2) * 2 // Force even number
        
        guard bytesToProcess > 0 else { return }
        
        let chunkToBuffer = pcmAccumulator.prefix(bytesToProcess)
        pcmAccumulator.removeFirst(bytesToProcess) // Keep the leftover byte if it was odd
        
        // 3. Scheduling
        lastAudioData.append(chunkToBuffer)
        let actualDataDuration = Double(lastAudioData.count / 2) / 24000.0
        self.duration = max(self.estimatedDuration, actualDataDuration)
        
        if !isDragging {
            guard let buffer = dataToBuffer(chunkToBuffer) else { return }
            playerNode.volume = volume
            
            self.scheduledBufferCount += 1
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.scheduledBufferCount -= 1
                    if !self.isStreamActive && self.scheduledBufferCount == 0 && self.isPlaying {
                         self.stop()
                    }
                }
            })
            
            // Start playback after a tiny safety buffer (250ms = 12000 bytes)
            if !hasStartedPlayback && lastAudioData.count > 12000 {
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
                
                // 🔊 HARDWARE SYNC: Only count time that physically left the speakers
                if let nodeTime = self.playerNode.lastRenderTime,
                   let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                    
                    let elapsedSamples = Double(playerTime.sampleTime)
                    // sampleTime can briefly be negative during engine startup
                    if elapsedSamples > 0 {
                        let elapsedSeconds = elapsedSamples / self.format.sampleRate
                        self.currentTime = self.pausedTime + elapsedSeconds
                    }
                }
                
                if !self.isDragging {
                    self.progress = self.duration > 0 ? min(1.0, self.currentTime / self.duration) : 0
                }
            }
    }

    func togglePause() {
        // 🔒 FIX: Refuse to play if memory is completely empty
        guard duration > 0 else { return } 
        
        if playerNode.isPlaying {
            // Save accumulated hardware time before pausing
            if let nodeTime = playerNode.lastRenderTime,
               let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
                let elapsedSamples = Double(playerTime.sampleTime)
                if elapsedSamples > 0 {
                    pausedTime += elapsedSamples / format.sampleRate
                }
            }
            playerNode.pause()
            engine.pause()
            isPlaying = false
        } else {
            try? engine.start()
            playerNode.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to percentage: Double) {
        guard !lastAudioData.isEmpty else { return }
        playerNode.stop()
        self.scheduledBufferCount = 0
        
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
                Task { @MainActor in
                    self?.scheduledBufferCount -= 1
                }
            })
            
            self.pausedTime = targetTime
            self.currentTime = targetTime
            
            if !engine.isRunning { try? engine.start() }
            playerNode.play()
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
        // Final flush of remaining data
        if pcmAccumulator.count > 0 {
            playChunk(Data(), volume: playerNode.volume)
        }
        if scheduledBufferCount == 0 && isPlaying { stop() }
    }
    
    func stop() {
        playerNode.stop()
        timer?.cancel()
        isPlaying = false
        progress = 0
        currentTime = 0
        pausedTime = 0
        hasStartedPlayback = false
        isStreamActive = false
        hasStrippedHeader = false
        scheduledBufferCount = 0
        lastAudioData = Data()
        pcmAccumulator = Data()
        headerAccumulator = Data()
        estimatedDuration = 0
        duration = 0
    }
    
    private func dataToBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count) / 2
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self), let channel = buffer.int16ChannelData?[0] {
                for i in 0..<Int(frameCount) { channel[i] = base[i] }
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
