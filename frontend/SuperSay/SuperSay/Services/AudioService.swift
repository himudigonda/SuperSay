import AVFoundation
import Combine

@MainActor
class AudioService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isDragging = false // Added to support Slider dragging logic
    
    private var player: AVAudioPlayer?
    private var timer: AnyCancellable?
    
    func play(data: Data, volume: Float) throws {
        stop() // Reset previous
        
        player = try AVAudioPlayer(data: data, fileTypeHint: "wav")
        player?.delegate = self
        player?.volume = volume
        player?.prepareToPlay()
        player?.play()
        
        self.duration = player?.duration ?? 0
        self.isPlaying = true
        startTimer()
    }
    
    func togglePause() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
            startTimer()
        }
    }
    
    func stop() {
        player?.stop()
        player = nil
        timer?.cancel()
        isPlaying = false
        progress = 0
        currentTime = 0
    }
    
    func seek(to percentage: Double) {
        guard let p = player else { return }
        p.currentTime = percentage * p.duration
        self.currentTime = p.currentTime
        if p.duration > 0 {
             self.progress = percentage
        }
    }
    
    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let p = self.player, p.isPlaying else { return }
                self.currentTime = p.currentTime
                if self.isDragging == false {
                    self.progress = p.duration > 0 ? p.currentTime / p.duration : 0
                }
            }
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
