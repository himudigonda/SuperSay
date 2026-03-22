import Combine
import SwiftUI

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
    @Published var isModelLoaded = false        // Model in ONNX session RAM
    @Published var selectedTab: String? = "home"

    // Clipboard monitoring for anticipatory pre-warm
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount

    @AppStorage("selectedVoice") var selectedVoice = "af_bella"
    @AppStorage("ttsEngine") var ttsEngine = "kokoro" {
        didSet { onEngineChanged() }
    }
    @AppStorage("kittenModel") var kittenModel = "nano" {
        didSet { onEngineChanged() }
    }
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

    /// Helper to get Font
    func appFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch selectedFontName {
        case "System Rounded":
            .system(size: size, weight: weight, design: .rounded)
        case "System Mono":
            .system(size: size, weight: weight, design: .monospaced)
        case "System Serif":
            .system(size: size, weight: weight, design: .serif)
        case "System Standard":
            .system(size: size, weight: weight, design: .default)
        case "Poppins":
            .custom("Poppins-Regular", size: size).weight(weight)
        default:
            .custom(selectedFontName, size: size).weight(weight)
        }
    }

    private static let kokoroVoices: [(id: String, display: String)] = [
        ("af_bella", "🇺🇸 Bella"), ("af_sarah", "🇺🇸 Sarah"),
        ("am_adam", "🇺🇸 Adam"), ("am_michael", "🇺🇸 Michael"),
        ("bf_emma", "🇬🇧 Emma"), ("bf_isabella", "🇬🇧 Isabella"),
        ("bm_george", "🇬🇧 George"), ("bm_lewis", "🇬🇧 Lewis"),
    ]

    private static let kittenVoices: [(id: String, display: String)] = [
        ("Bella", "Bella"), ("Jasper", "Jasper"), ("Luna", "Luna"), ("Bruno", "Bruno"),
        ("Rosie", "Rosie"), ("Hugo", "Hugo"), ("Kiki", "Kiki"), ("Leo", "Leo"),
    ]

    var availableVoices: [(id: String, display: String)] {
        ttsEngine == "kitten" ? Self.kittenVoices : Self.kokoroVoices
    }

    private func onEngineChanged() {
        guard isBackendOnline else { return }
        // Reset voice if current selection isn't valid for the new engine
        let validIDs = availableVoices.map(\.id)
        if !validIDs.contains(selectedVoice) {
            selectedVoice = ttsEngine == "kitten" ? "Bella" : "af_bella"
        }
        let engine = ttsEngine
        let model: String? = engine == "kitten" ? kittenModel : nil
        Task { try? await backend.switchEngine(engine: engine, model: model) }
    }

    /// Computed property for display
    var currentVoiceDisplay: String {
        selectedVoice.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Computed property for online status
    var isOnline: Bool {
        isBackendOnline
    }

    private var currentSpeakTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    init(backend: BackendService, system: SystemService, audio: AudioService, history: HistoryManager) {
        self.backend = backend
        self.system = system
        self.audio = audio
        self.history = history

        setupBindings()
        startHeartbeat()
        startPrewarmObservers()
    }

    private func setupBindings() {
        // Sync Audio Service state to local status
        audio.$isPlaying
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if isPlaying {
                    status = .speaking
                    if enableDucking { system.setMusicVolume(ducked: true) }
                } else {
                    // FIX: Differentiate between paused and stopped
                    if status == .speaking {
                        // If audio stopped playing but we were speaking, it's a PAUSE or STOP
                        // We check the audio player's current time vs duration to guess
                        if audio.currentTime > 0.1, audio.currentTime < audio.duration - 0.1 {
                            status = .paused
                        } else {
                            status = .ready
                        }
                    }

                    if enableDucking {
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
        if let text {
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
        // --- FIX: Cancel the previous stream task if it exists ---
        currentSpeakTask?.cancel()

        currentSpeakTask = Task {
            print("DEBUG [DashboardVM] Starting new speak task")
            status = .thinking

            let cleaned = TextProcessor.sanitize(text, options: .init(cleanURLs: cleanURLs, cleanHandles: true, fixLigatures: true, expandAbbr: true, expandNumbers: true))
            audio.setEstimatedDuration(textLength: cleaned.count, speed: speechSpeed)

            // This resets the AudioService buffers
            audio.prepareForStream()

            let stream = backend.streamAudio(
                text: cleaned,
                voice: selectedVoice,
                speed: speechSpeed,
                volume: speechVolume
            )

            for await chunk in stream {
                // Check if this task was cancelled while we were waiting for a chunk
                if Task.isCancelled {
                    print("DEBUG [DashboardVM] Task cancelled, exiting loop")
                    return
                }

                if status == .thinking { status = .speaking }
                audio.playChunk(chunk, volume: Float(speechVolume))
            }

            if !Task.isCancelled {
                audio.finishStream()
                history.log(text: cleaned, voice: selectedVoice)
                MetricsService.shared.trackGeneration(charCount: cleaned.count)
            }
        }
    }

    func togglePlayback() {
        if audio.duration == 0 {
            // Show the error message in the UI pill
            status = .error("Nothing to play. Select text and press Cmd+Shift+.")

            // Auto-clear the error and return to "READY" after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if case let .error(msg) = self.status, msg == "Nothing to play. Select text and press Cmd+Shift+." {
                    self.status = .ready
                }
            }
        } else {
            audio.togglePause()
        }
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
                let health = await backend.checkHealth()
                isBackendOnline = health.isOnline
                isModelLoaded = health.isModelLoaded

                if health.isOnline {
                    isBackendInitializing = false
                } else {
                    let launching = backend.isLaunching
                    isBackendInitializing = launching
                    await backend.start()
                }

                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            }
        }
    }

    /// Pre-warm the model before the user speaks, hiding the ~1.3 s cold-reload cost.
    ///
    /// Two signals trigger this:
    /// 1. The clipboard changes — user just copied text and will likely press the hotkey.
    /// 2. The app becomes active — user switched to SuperSay to type/speak directly.
    ///
    /// In both cases the backend starts loading the ONNX model in the background.
    /// By the time the user actually presses the hotkey (typically 0.5–3 s later),
    /// the model is already warm and /speak returns audio with normal ~300 ms latency.
    private func startPrewarmObservers() {
        // Signal 1: clipboard change — always prewarm (model load + lookahead cache).
        // No !isModelLoaded guard: even when warm, we want to pre-compute the first
        // audio segment so /speak finds it cached and streams it in <20ms.
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let current = NSPasteboard.general.changeCount
                guard current != self.lastPasteboardChangeCount else { return }
                self.lastPasteboardChangeCount = current
                guard self.isBackendOnline else { return }
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                let voice = self.selectedVoice
                let speed = self.speechSpeed
                Task { await self.backend.prewarm(text: text, voice: voice, speed: speed) }
            }
            .store(in: &cancellables)

        // Signal 2: app focus — only loads the model (no lookahead; unknown text).
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self, self.isBackendOnline, !self.isModelLoaded else { return }
                Task { await self.backend.prewarm() }
            }
            .store(in: &cancellables)
    }

    /// --- FONT PANEL SUPPORT ---
    func showFontPanel() {
        NSFontManager.shared.target = self
        NSFontManager.shared.action = #selector(changeFont(_:))
        NSFontPanel.shared.orderFront(nil)
        NSFontPanel.shared.isEnabled = true
    }

    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let newFont = fontManager.convert(.systemFont(ofSize: 12))
        selectedFontName = newFont.familyName ?? "System Standard"
    }

    /// --- UPDATE CHECKER ---
    func checkForUpdates(manual: Bool = true) {
        Task {
            // Fetch ALL releases to aggregate changelogs
            guard let url = URL(string: "https://api.github.com/repos/himudigonda/SuperSay/releases") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)

                let currentVersion = "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")

                // Filter releases newer than current
                let newer = releases.filter { $0.tagName != currentVersion && isNewer($0.tagName, than: currentVersion) }

                if let latest = newer.first {
                    print("🚀 New version available: \(latest.tagName)")
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

        for i in 0 ..< min(v1.count, v2.count) {
            if v1[i] > v2[i] { return true }
            if v1[i] < v2[i] { return false }
        }
        return v1.count > v2.count
    }

    func exportLogs() {
        Task {
            backend.exportLogs()
        }
    }
}

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
    }

    struct Asset: Codable {
        let name: String
        let browserDownloadUrl: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }
}
