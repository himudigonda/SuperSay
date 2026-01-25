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
    @Published var isBackendInitializing = true // Start as initializing
    @Published var selectedTab: String? = "home"
    
    @AppStorage("selectedVoice") var selectedVoice = "af_bella"
    @AppStorage("speechSpeed") var speechSpeed = 1.0
    @AppStorage("speechVolume") var speechVolume = 1.0
    @AppStorage("enableDucking") var enableDucking = true
    @AppStorage("cleanURLs") var cleanURLs = true
    @AppStorage("appTheme") var appTheme = "system" // system, light, dark
    @AppStorage("telemetryEnabled") var telemetryEnabled = true
    @AppStorage("selectedFontName") var selectedFontName = "System Rounded"
    
    // Update State
    @Published var availableUpdate: GitHubRelease?
    @Published var allRelevantReleases: [GitHubRelease] = []
    @Published var showUpdateSheet = false
    @Published var hasUpdate = false
    
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
        print("⌨️ DashboardViewModel: speakSelection triggered")
        if let text = text {
             await speak(text: text)
             return
        }
        guard let text = SelectionManager.getSelectedText(), !text.isEmpty else {
            print("⚠️ DashboardViewModel: No text found in selection.")
            return
        }
        print("🎤 DashboardViewModel: Sending \(text.count) chars to backend...")
        await speak(text: text)
    }
    
    func speak(text: String) async {
        status = .thinking
        
        // 1. Pre-processing & Splitting
        let cleaned = TextProcessor.sanitize(text, options: .init(cleanURLs: cleanURLs, cleanHandles: true, fixLigatures: true, expandAbbr: true))
        let sentences = splitIntoSentences(cleaned)
        
        print("🎙️ DashboardViewModel: Parallelizing \(sentences.count) sentences...")
        audio.prepareForStream()
        
        // 2. Start parallel requests for each sentence
        // We'll process them in windows (max 5 at a time) to avoid overwhelming the backend
        let windowSize = 5
        for i in stride(from: 0, to: sentences.count, by: windowSize) {
            let end = min(i + windowSize, sentences.count)
            let window = sentences[i..<end]
            
            // Start all streams in this window
            var streams: [AsyncStream<Data>] = []
            for sentence in window {
                let stream = await backend.streamAudio(
                    text: String(sentence),
                    voice: selectedVoice,
                    speed: speechSpeed,
                    volume: speechVolume
                )
                streams.append(stream)
            }
            
            // Sequential playback of parallel-fetched streams
            for (idx, stream) in streams.enumerated() {
                for await chunk in stream {
                    if status == .thinking {
                        status = .speaking
                    }
                    audio.playChunk(chunk, volume: Float(speechVolume))
                }
                print("✅ DashboardViewModel: Finished sentence \(i + idx + 1)/\(sentences.count)")
            }
        }
        
        audio.finishStream()
        print("🎬 DashboardViewModel: Total stream finished")
        history.log(text: cleaned, voice: selectedVoice)
        MetricsService.shared.trackGeneration(charCount: cleaned.count)
    }
    
    private func splitIntoSentences(_ text: String) -> [String] {
        // Use a simple split but handle common abbreviations
        // A better approach would be NSLinguisticTagger, but this is faster for TTS chunks
        
        var result: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        let regex = try? NSRegularExpression(pattern: "[^.!?]+[.!?]*", options: [])
        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let matchRange = match?.range, let swiftRange = Range(matchRange, in: text) {
                let s = text[swiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { result.append(s) }
            }
        }
        
        return result.isEmpty ? [text] : result
    }
    
    func startHeartbeat() {
        Task {
            while true {
                isBackendOnline = await backend.checkHealth()
                
                DispatchQueue.main.async {
                    if self.isBackendOnline {
                         self.isBackendInitializing = false
                    } else {
                         // If we are offline, we are likely initializing or failed
                         // We let BackendService's isLaunching state dictate this implicitly, 
                         // but for now, if offline, we assume initializing loop
                         Task {
                             let launching = await self.backend.isLaunching
                             DispatchQueue.main.async {
                                 self.isBackendInitializing = launching
                             }
                         }
                    }
                }
                
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
    func checkForUpdates(manual: Bool = true) {
        Task {
            // Fetch ALL releases to aggregate changelogs
            guard let url = URL(string: "https://api.github.com/repos/himudigonda/SuperSay/releases") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                
                let currentVersion = "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                
                // Filter releases newer than current
                let newer = releases.filter { $0.tag_name != currentVersion && isNewer($0.tag_name, than: currentVersion) }
                
                if let latest = newer.first {
                    print("🚀 New version available: \(latest.tag_name)")
                    self.availableUpdate = latest
                    self.allRelevantReleases = newer
                    self.hasUpdate = true
                    self.showUpdateSheet = true
                } else if manual {
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
    
    private func isNewer(_ version: String, than current: String) -> Bool {
        let v1 = version.replacingOccurrences(of: "v", with: "").split(separator: ".").compactMap { Int($0) }
        let v2 = current.replacingOccurrences(of: "v", with: "").split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<min(v1.count, v2.count) {
            if v1[i] > v2[i] { return true }
            if v1[i] < v2[i] { return false }
        }
        return v1.count > v2.count
    }
    func exportLogs() {
        Task {
            await backend.exportLogs()
        }
    }
}

struct GitHubRelease: Codable {
    let tag_name: String
    let name: String
    let body: String
    let html_url: String
    let assets: [Asset]
    
    struct Asset: Codable {
        let name: String
        let browser_download_url: URL
    }
}
