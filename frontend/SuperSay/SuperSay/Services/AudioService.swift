import AVFoundation
import Combine
import UserNotifications
import AppKit

@MainActor
class AudioService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isDragging = false // Added to support Slider dragging logic
    
    private var player: AVAudioPlayer?
    private var timer: AnyCancellable?
    private var lastAudioData: Data?
    
    func play(data: Data, volume: Float) throws {
        print("🔊 AudioService: Received audio data (\(data.count) bytes)")
        stop() // Reset previous
        self.lastAudioData = data
        
        player = try AVAudioPlayer(data: data, fileTypeHint: "wav")
        player?.delegate = self
        player?.volume = volume
        player?.prepareToPlay()
        player?.play()
        
        self.duration = player?.duration ?? 0
        self.isPlaying = true
        print("▶️ AudioService: Playback started (Duration: \(duration)s)")
        startTimer()
    }
    
    func togglePause() {
        if player == nil, let data = lastAudioData {
            // Re-initialize if the player was previously cleared for some reason
            try? play(data: data, volume: player?.volume ?? 1.0)
            return
        }
        
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
        } else {
            // If we are at the end, restart
            if p.currentTime >= p.duration - 0.1 {
                p.currentTime = 0
            }
            p.play()
            isPlaying = true
            startTimer()
        }
    }
    
    func stop() {
        player?.pause() // Use pause + currentTime = 0 instead of stop to keep player alive
        player?.currentTime = 0
        timer?.cancel()
        isPlaying = false
        progress = 0
        currentTime = 0
    }
    
    func reset() {
        stop()
        player = nil
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
    
    func exportToDesktop() {
        print("📂 AudioService: Export triggered")
        guard let data = lastAudioData else {
            print("❌ AudioService: Export failed - lastAudioData is nil")
            showNotification(title: "Export Failed", body: "No audio to export.")
            return
        }
        
        print("📦 AudioService: Exporting \(data.count) bytes of data")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SuperSay_\(formatter.string(from: Date())).wav"
        
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let fileURL = desktopURL.appendingPathComponent(filename)
        print("📍 AudioService: Target path: \(fileURL.path)")
        
        do {
            try data.write(to: fileURL)
            print("✅ AudioService: File written successfully to Desktop")
            showNotification(title: "Export Successful", body: "Saved to Desktop: \(filename)")
            TelemetryService.shared.trackExport()
        } catch {
            print("❌ AudioService: Write error - \(error.localizedDescription)")
            showNotification(title: "Export Failed", body: error.localizedDescription)
        }
    }
    
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
