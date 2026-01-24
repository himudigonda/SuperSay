import SwiftUI
import KeyboardShortcuts
import Combine
import UserNotifications
import NaturalLanguage

@MainActor
class SuperSayStore: ObservableObject {
    // Services
    @Published var audio = AudioEngine()
    @Published var history = HistoryManager()
    @Published var pdf = PDFEngine()
    @Published var status: AppStatus = .ready
    @Published var isOnline = false
    @Published var launchManager = LaunchManager()
    @Published var selectedTab: String = "home"
    
    // Backend process reference for lifecycle management
    private var serverProcess: Process?
    
    // Configs
    @AppStorage("cleanURLs") var cleanURLs = true
    @AppStorage("fixLigatures") var fixLigatures = true
    @AppStorage("selectedVoice") var selectedVoice = "af_bella"
    @AppStorage("speechSpeed") var speechSpeed = 1.0
    @AppStorage("enableDucking") var enableDucking = true
    @AppStorage("appTheme") var appTheme = "system"
    @AppStorage("showNotifications") var showNotifications = true
    @AppStorage("speechVolume") var speechVolume = 1.0 {
        didSet { audio.setVolume(Float(speechVolume)) }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var speechTask: Task<Void, Never>?
    
    var currentVoiceDisplay: String {
        selectedVoice.replacingOccurrences(of: "af_", with: "")
            .replacingOccurrences(of: "am_", with: "")
            .replacingOccurrences(of: "bf_", with: "")
            .replacingOccurrences(of: "bm_", with: "")
            .uppercased()
    }
    
    init() {
        setupHotkeys()
        startHeartbeat()
        requestNotificationPermission()
        
        // Audio State Listener
        audio.$isPlaying
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self = self else { return }
                if playing {
                    self.status = .speaking
                    if self.enableDucking { self.setDucking(active: true) }
                } else if self.status == .speaking {
                    self.status = .ready
                    if self.enableDucking {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.setDucking(active: false)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Language Detection
    private func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return "en-us" }
        
        switch lang {
        case .english: return "en-us"
        case .japanese: return "ja-jp"
        case .simplifiedChinese, .traditionalChinese: return "zh-cn"
        case .french: return "fr-fr"
        case .german: return "de-de"
        case .spanish: return "es-es"
        case .italian: return "it-it"
        case .korean: return "ko-kr"
        default: return "en-us"
        }
    }

    // MARK: - Main Action
    func speakSelection(text: String? = nil) async {
        speechTask?.cancel()
        
        speechTask = Task {
            let input = text ?? SelectionManager.getSelectedText()
            guard let raw = input, !raw.isEmpty else {
                print("⚠️ No text selected or empty input")
                return
            }
            
            print("🎤 Speaking: \(raw.prefix(50))...")
            
            if showNotifications { sendNotification(text: String(raw.prefix(100)) + "...") }
            
            // Detect language and clean text
            let lang = detectLanguage(for: raw)
            let cleaned = TextProcessor.sanitize(raw, options: .init(cleanURLs: cleanURLs, cleanHandles: true, fixLigatures: fixLigatures, expandAbbr: true))
            
            status = .thinking
            
            // Wait for server to be ready before proceeding
            if !self.isOnline {
                print("⏳ Waiting for server to be ready...")
                for _ in 1...10 {
                    if self.isOnline { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                if !self.isOnline {
                    print("❌ Server not available")
                    self.status = .error("Server not ready. Please wait a moment and try again.")
                    return
                }
            }
            
            do {
                // Send FULL text to Python - it handles all chunking now!
                // No more TaskGroup or WAV byte patching!
                let audioData = try await fetchFullAudio(text: cleaned, lang: lang)
                
                print("📊 Received \(audioData.count) bytes of audio")
                
                if enableDucking { setDucking(active: true) }
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                if Task.isCancelled { return }
                
                // AudioEngine simply plays the clean WAV returned by Python
                try audio.play(data: audioData, volume: Float(min(speechVolume, 1.0)))
                history.log(text: cleaned, voice: selectedVoice)
                
            } catch {
                print("❌ SuperSay Error: \(error)")
                if !Task.isCancelled { status = .error("Error: \(error.localizedDescription)") }
            }
        }
    }

    private func fetchFullAudio(text: String, lang: String) async throws -> Data {
        let url = URL(string: "http://127.0.0.1:8000/speak")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // Longer timeout for large texts
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, 
            "voice": selectedVoice, 
            "speed": speechSpeed, 
            "volume": speechVolume, // Only applied for boost > 1.0 in Python
            "lang": lang
        ])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("📡 API Response: \(statusCode), \(data.count) bytes")
        
        guard statusCode == 200 else { 
            print("❌ Bad response: \(statusCode)")
            throw URLError(.badServerResponse) 
        }
        return data
    }

    // MARK: - Utils
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(text: String) {
        let content = UNMutableNotificationContent()
        content.title = "SuperSay"
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func setupHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .playText) { [weak self] in Task { await self?.speakSelection() } }
        KeyboardShortcuts.onKeyUp(for: .togglePause) { [weak self] in self?.audio.togglePause() }
        KeyboardShortcuts.onKeyUp(for: .stopText) { [weak self] in 
            self?.audio.stop()
            self?.status = .ready
        }
        KeyboardShortcuts.onKeyUp(for: .exportToDesktop) { [weak self] in Task { await self?.exportToDesktop() } }
    }
    
    // MARK: - Server Lifecycle
    func startHeartbeat() {
        Task {
            var firstCheck = true
            while true {
                do {
                    let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8000/health")!)
                    self.isOnline = ((response as? HTTPURLResponse)?.statusCode == 200)
                } catch {
                    self.isOnline = false
                    if firstCheck { launchBackend() }
                }
                firstCheck = false
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func launchBackend() {
        guard serverProcess == nil else { return }
        guard let url = Bundle.main.url(forResource: "SuperSayServer", withExtension: nil) else {
            print("❌ SuperSayServer binary not found in bundle")
            return
        }
        
        let process = Process()
        process.executableURL = url
        do {
            try process.run()
            serverProcess = process
            print("🚀 [Launch] SuperSayServer process started, waiting for server to be ready...")
            
            // Wait for server to be ready (model loading takes a few seconds)
            Task {
                await waitForServerReady()
            }
        } catch {
            print("❌ Failed to launch backend: \(error)")
        }
    }
    
    private func waitForServerReady() async {
        let maxAttempts = 30  // Try for up to 30 seconds
        for attempt in 1...maxAttempts {
            do {
                let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8000/health")!)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    print("✅ [Ready] SuperSayServer is online after \(attempt) seconds")
                    self.isOnline = true
                    return
                }
            } catch {
                // Server not ready yet, keep waiting
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        print("⚠️ Server did not become ready within \(maxAttempts) seconds")
    }

    func stopBackend() {
        serverProcess?.terminate()
        serverProcess = nil
        print("🛑 Backend terminated")
    }

    private func setDucking(active: Bool) {
        let targetVol = active ? 10 : 85
        let script = """
        on fadeById(bundleId, targetVolume)
            try
                tell application "System Events" to set isRunning to exists (processes where bundle identifier is bundleId)
                if isRunning then
                    tell application id bundleId
                        set sound volume to targetVolume
                    end tell
                end if
            end try
        end fadeById
        fadeById("com.apple.Music", \(targetVol))
        fadeById("com.spotify.client", \(targetVol))
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            try? task.run()
        }
    }
    
    func resetSystemPermissions() {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "AppleEvents"]
        try? task.run()
    }
    
    // MARK: - Export
    func exportToDesktop() async {
        guard let input = SelectionManager.getSelectedText(), !input.isEmpty else {
            print("⚠️ Export: No text selected")
            return
        }
        status = .thinking
        do {
            print("📤 Exporting: \(input.prefix(50))...")
            let lang = detectLanguage(for: input)
            let cleaned = TextProcessor.sanitize(input, options: .init(cleanURLs: cleanURLs, cleanHandles: true, fixLigatures: fixLigatures, expandAbbr: true))
            let data = try await fetchFullAudio(text: cleaned, lang: lang)
            
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let url = desktop.appendingPathComponent("SuperSay_\(Int(Date().timeIntervalSince1970)).wav")
            try data.write(to: url)
            print("✅ Exported to: \(url.path)")
            status = .ready
        } catch {
            print("❌ Export Error: \(error)")
            status = .error("Export: \(error.localizedDescription)")
        }
    }
}
