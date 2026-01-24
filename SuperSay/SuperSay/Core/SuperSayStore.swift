import SwiftUI
import KeyboardShortcuts
import Combine
import UserNotifications
import NaturalLanguage

@MainActor
class SuperSayStore: ObservableObject {
    // MARK: - Services
    @Published var audio = AudioEngine()
    @Published var history = HistoryManager()
    @Published var pdf = PDFEngine()
    @Published var status: AppStatus = .ready
    @Published var isOnline = false
    @Published var launchManager = LaunchManager()
    @Published var selectedTab: String = "home"
    
    // MARK: - Process Management
    private var serverProcess: Process?
    private var cancellables = Set<AnyCancellable>()
    private var speechTask: Task<Void, Never>?
    
    // MARK: - User Settings
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
    
    // MARK: - Computed Properties
    var currentVoiceDisplay: String {
        selectedVoice.replacingOccurrences(of: "af_", with: "")
            .replacingOccurrences(of: "am_", with: "")
            .replacingOccurrences(of: "bf_", with: "")
            .replacingOccurrences(of: "bm_", with: "")
            .uppercased()
    }
    
    // MARK: - Lifecycle
    init() {
        print("🔵 SuperSayStore: Init")
        setupHotkeys()
        startHeartbeat()
        requestNotificationPermission()
        
        // Audio State Listener (Ducking Control)
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
    
    // MARK: - Core Actions
    
    private func detectLanguage(for text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return "en-us" }
        switch lang {
        case .english: return "en-us"
        default: return "en-us"
        }
    }

    func speakSelection(text: String? = nil) async {
        speechTask?.cancel()
        
        speechTask = Task {
            let input = text ?? SelectionManager.getSelectedText()
            guard let raw = input, !raw.isEmpty else {
                print("⚠️ No text selected")
                return
            }
            
            if showNotifications { sendNotification(text: String(raw.prefix(100)) + "...") }
            
            let lang = detectLanguage(for: raw)
            let cleaned = TextProcessor.sanitize(raw, options: .init(cleanURLs: cleanURLs, cleanHandles: true, fixLigatures: fixLigatures, expandAbbr: true))
            
            status = .thinking
            
            if !self.isOnline {
                for i in 1...10 {
                    if self.isOnline { break }
                    print("... waiting for server \(i)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                if !self.isOnline {
                    status = .error("Server not ready.")
                    return
                }
            }
            
            do {
                let audioData = try await fetchFullAudio(text: cleaned, lang: lang)
                
                // WAV Header check
                if audioData.count >= 4 {
                    let header = audioData.prefix(4).map { String(format: "%02hhx", $0) }.joined()
                    if header != "52494646" {
                        status = .error("Invalid server response.")
                        return
                    }
                }
                
                try audio.play(data: audioData, volume: Float(min(speechVolume, 1.0)))
                history.log(text: cleaned, voice: selectedVoice)
                
            } catch {
                print("❌ Error in speakSelection: \(error)")
                status = .error("Error: \(error.localizedDescription)")
            }
        }
    }

    private func fetchFullAudio(text: String, lang: String) async throws -> Data {
        let url = URL(string: "http://127.0.0.1:8000/speak")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "voice": selectedVoice,
            "speed": speechSpeed,
            "lang": lang
        ])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Server Lifecycle
    
    func startHeartbeat() {
        Task {
            var firstCheck = true
            while true {
                do {
                    let (_, res) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8000/health")!)
                    self.isOnline = (res as? HTTPURLResponse)?.statusCode == 200
                } catch {
                    self.isOnline = false
                    if firstCheck { launchBackend() }
                }
                firstCheck = false
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func launchBackend() {
        guard serverProcess == nil else { return }
        guard let url = Bundle.main.url(forResource: "SuperSayServer", withExtension: nil) else { return }
        
        let process = Process()
        process.executableURL = url
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        
        do {
            try process.run()
            serverProcess = process
        } catch {
            print("❌ Failed to launch backend: \(error)")
        }
    }
    
    func stopBackend() {
        serverProcess?.terminate()
        serverProcess = nil
        
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-9", "SuperSayServer"]
        try? task.run()
    }

    // MARK: - System Utilities
    
    private func setDucking(active: Bool) {
        let targetVol = active ? 10 : 85
        let scriptSource = """
        try
            tell application id "com.apple.Music"
                if it is running then set sound volume to \(targetVol)
            end tell
        end try
        try
            tell application id "com.spotify.client"
                if it is running then set sound volume to \(targetVol)
            end tell
        end try
        """
        
        DispatchQueue.global(qos: .userInteractive).async {
            var errorDict: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&errorDict)
                if let error = errorDict { print("⚠️ Ducking Error: \(error)") }
            }
        }
    }
    
    func resetSystemPermissions() {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "AppleEvents"]
        try? task.run()
    }
    
    func exportToDesktop() async {
        guard let input = SelectionManager.getSelectedText(), !input.isEmpty else { return }
        status = .thinking
        do {
            let lang = detectLanguage(for: input)
            let cleaned = TextProcessor.sanitize(input, options: .init(cleanURLs: cleanURLs, cleanHandles: true, fixLigatures: fixLigatures, expandAbbr: true))
            let data = try await fetchFullAudio(text: cleaned, lang: lang)
            
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let url = desktop.appendingPathComponent("SuperSay_\(Int(Date().timeIntervalSince1970)).wav")
            try data.write(to: url)
            status = .ready
        } catch {
            status = .error("Export failed.")
        }
    }

    // MARK: - Helpers
    
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
}
