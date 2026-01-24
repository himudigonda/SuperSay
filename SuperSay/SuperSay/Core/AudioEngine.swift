import AVFoundation
import Combine

@MainActor
class AudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    
    // We use a separate property for the progress to avoid heavy calculations in the View
    @Published var progress: Double = 0.0
    
    private var player: AVAudioPlayer?
    private var timer: AnyCancellable?
    
    // Flag to stop the timer from overwriting the slider while the user is dragging
    var isDragging = false
    
    func play(data: Data, volume: Float = 1.0) throws {
        stop()
        
        player = try AVAudioPlayer(data: data)
        player?.delegate = self
        player?.volume = volume
        player?.prepareToPlay()
        player?.play()
        
        self.duration = player?.duration ?? 0
        self.isPlaying = true
        
        startTimer()
    }
    
    func setVolume(_ volume: Float) {
        player?.volume = volume
    }
    
    private func startTimer() {
        timer?.cancel()
        // Use a high-frequency timer on the .common mode so it doesn't stop during scrolling/dragging
        timer = Timer.publish(every: 0.03, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let p = self.player, p.isPlaying, !self.isDragging else { return }
                self.currentTime = p.currentTime
                self.progress = p.duration > 0 ? p.currentTime / p.duration : 0
            }
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
    
    func seek(to percentage: Double) {
        guard let p = player else { return }
        let targetTime = percentage * p.duration
        p.currentTime = targetTime
        self.currentTime = targetTime
        self.progress = percentage
    }
    
    func stop() {
        player?.stop()
        timer?.cancel()
        timer = nil
        self.progress = 0
        self.currentTime = 0
        self.isPlaying = false
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
