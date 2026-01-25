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
    @AppStorage("selectedFontName") var selectedFontName = "System Rounded"
    
    // Helper to get Font
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch selectedFontName {
        case "System Rounded":
            return .system(size: size, weight: weight, design: .rounded)
        case "System Mono":
            return .system(size: size, weight: weight, design: .monospaced)
        case "System Serif":
            return .system(size: size, weight: weight, design: .serif)
        case "System Standard":
            return .system(size: size, weight: weight, design: .default)
        case "Poppins":
            return .custom("Poppins-Regular", size: size).weight(weight)
        default:
            return .custom(selectedFontName, size: size).weight(weight)
        }
    }
    
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
        
        audio.prepareForStream()
        
        let stream = await backend.streamAudio(
            text: cleaned,
            voice: selectedVoice,
            speed: speechSpeed,
            volume: speechVolume
        )
        
        do {
            for await chunk in stream {
                if status == .thinking {
                    status = .speaking
                }
                audio.playChunk(chunk, volume: Float(speechVolume))
            }
            
            audio.finishStream()
            print("🎬 DashboardViewModel: Stream finished")
            history.log(text: cleaned, voice: selectedVoice)
            MetricsService.shared.trackGeneration(charCount: cleaned.count)
            
        } catch {
            print("❌ DashboardViewModel: Stream error: \(error)")
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
    
    // --- FONT PANEL SUPPORT ---
    func showFontPanel() {
        NSFontManager.shared.target = self
        NSFontManager.shared.action = #selector(changeFont(_:))
        NSFontPanel.shared.orderFront(nil)
        NSFontPanel.shared.isEnabled = true
    }
    
    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let newFont = fontManager.convert(.systemFont(ofSize: 12))
        self.selectedFontName = newFont.familyName ?? "System Standard"
    }
    
    // --- UPDATE CHECKER ---
    func checkForUpdates() {
        Task {
            guard let url = URL(string: "https://api.github.com/repos/himudigonda/SuperSay/releases/latest") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                
                let currentVersion = "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                
                if release.tag_name != currentVersion {
                    print("🚀 New version available: \(release.tag_name)")
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Update Available"
                        alert.informativeText = "A new version of SuperSay (\(release.tag_name)) is available."
                        alert.addButton(withTitle: "Download")
                        alert.addButton(withTitle: "Cancel")
                        
                        if alert.runModal() == .alertFirstButtonReturn {
                            if let link = URL(string: release.html_url) {
                                NSWorkspace.shared.open(link)
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "You're Up to Date"
                        alert.informativeText = "SuperSay \(currentVersion) is the latest version."
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                print("❌ Update check failed: \(error)")
            }
        }
    }
}

struct GitHubRelease: Codable {
    let tag_name: String
    let html_url: String
}
