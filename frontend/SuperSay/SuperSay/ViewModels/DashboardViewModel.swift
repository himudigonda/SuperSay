import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    // Dependencies
    private let backend: BackendService
    private let system: SystemService
    let audio: AudioService
    private let persistence: PersistenceService
    
    // State
    @Published var status: AppStatus = .ready
    @Published var isBackendOnline = false
    @AppStorage("selectedVoice") var selectedVoice = "af_bella"
    @AppStorage("speechSpeed") var speechSpeed = 1.0
    @AppStorage("speechVolume") var speechVolume = 1.0
    @AppStorage("enableDucking") var enableDucking = true
    @AppStorage("cleanURLs") var cleanURLs = true
    
    // Computed property for display
    var currentVoiceDisplay: String {
        selectedVoice.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    // Computed property for online status
    var isOnline: Bool {
        isBackendOnline
    }

    private var cancellables = Set<AnyCancellable>()
    
    init(backend: BackendService, system: SystemService, audio: AudioService, persistence: PersistenceService) {
        self.backend = backend
        self.system = system
        self.audio = audio
        self.persistence = persistence
        
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
                    if self.status == .speaking { self.status = .ready }
                    if self.enableDucking { 
                        // Delay unduck slightly for smooth transition
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.system.setMusicVolume(ducked: false) 
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func speakSelection() async {
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
            
            try audio.play(data: data, volume: Float(speechVolume))
            persistence.log(text: cleaned, voice: selectedVoice)
            
        } catch {
            print("Error: \(error)")
            status = .error(error.localizedDescription)
        }
    }
    
    func startHeartbeat() {
        Task {
            while true {
                isBackendOnline = await backend.checkHealth()
                if !isBackendOnline { backend.start() }
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            }
        }
    }
}
