import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    // Dependencies
    private let backend: BackendService
    private let system: SystemService
    let audio: AudioService
    private let history: HistoryManager
    
    // State
    @Published var status: AppStatus = .ready
    @Published var isBackendOnline = false
    @Published var selectedTab: String? = "home"
    
    @AppStorage("selectedVoice") var selectedVoice = "af_bella"
    @AppStorage("speechSpeed") var speechSpeed = 1.0
    @AppStorage("speechVolume") var speechVolume = 1.0
    @AppStorage("enableDucking") var enableDucking = true
    @AppStorage("cleanURLs") var cleanURLs = true
    @AppStorage("appTheme") var appTheme = "system" // system, light, dark
    @AppStorage("telemetryEnabled") var telemetryEnabled = true
    
    // Computed property for display
    var currentVoiceDisplay: String {
        selectedVoice.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    // Computed property for online status
    var isOnline: Bool {
        isBackendOnline
    }

    private var cancellables = Set<AnyCancellable>()
    
    init(backend: BackendService, system: SystemService, audio: AudioService, history: HistoryManager) {
        self.backend = backend
        self.system = system
        self.audio = audio
        self.history = history
        
        setupBindings()
        startHeartbeat()
    }
    
    private func setupBindings() {
        // Sync Audio Service state to local status
        audio.$isPlaying
            .sink { [weak self] isPlaying in
                guard let self = self else { return }
                if isPlaying {
                    self.status = .speaking
                    if self.enableDucking { self.system.setMusicVolume(ducked: true) }
                } else {
                    // FIX: Differentiate between paused and stopped
                    if self.status == .speaking {
                        // If audio stopped playing but we were speaking, it's a PAUSE or STOP
                        // We check the audio player's current time vs duration to guess
                        if self.audio.currentTime > 0.1 && self.audio.currentTime < self.audio.duration - 0.1 {
                            self.status = .paused
                        } else {
                            self.status = .ready
                        }
                    }
                    
                    if self.enableDucking { 
                        // Only unduck if we are truly done or paused for a while
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if !self.audio.isPlaying {
                                self.system.setMusicVolume(ducked: false) 
                            }
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func speakSelection(text: String? = nil) async {
        if let text = text {
             await speak(text: text)
             return
        }
        guard let text = SelectionManager.getSelectedText(), !text.isEmpty else { return }
        await speak(text: text)
    }
    
    func speak(text: String) async {
        status = .thinking
        
        // Pre-processing
        let cleaned = TextProcessor.sanitize(text, options: .init(cleanURLs: cleanURLs, cleanHandles: true, fixLigatures: true, expandAbbr: true))
        
        do {
            let data = try await backend.generateAudio(
                text: cleaned,
                voice: selectedVoice,
                speed: speechSpeed,
                volume: speechVolume
            )
            
            print("🎬 DashboardViewModel: Audio data received, sending to AudioService")
            try audio.play(data: data, volume: Float(speechVolume))
            history.log(text: cleaned, voice: selectedVoice)
            MetricsService.shared.trackGeneration(charCount: cleaned.count)
            
        } catch {
            print("Error: \(error)")
            status = .error(error.localizedDescription)
        }
    }
    
    func startHeartbeat() {
        Task {
            while true {
                isBackendOnline = await backend.checkHealth()
                if !isBackendOnline { await backend.start() }
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000) // 5 seconds between checks
            }
        }
    }
}
