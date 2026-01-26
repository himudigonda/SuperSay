import SwiftUI
import KeyboardShortcuts
import UserNotifications

@main
struct SuperSayApp: App {
    // 1. Single Sources of Truth (Services)
    @StateObject private var audio: AudioService
    @StateObject private var history: HistoryManager
    @StateObject private var pdf: PDFService
    @StateObject private var launchManager: LaunchManager
    
    // 2. Logic Controller (ViewModel)
    @StateObject private var dashboardVM: DashboardViewModel
    
    // 3. Backend (Kept private, managed by VM, but we own the instance to stop deinit)
    private let backend: BackendService
    
    init() {
        // 1. REDIRECT FRONTEND LOGS TO FILE
        let bundleID = Bundle.main.bundleIdentifier ?? "com.himudigonda.SuperSay"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        
        let logURL = appSupport.appendingPathComponent("frontend.log")
        
        // Clear old log
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        
        // Redirect stdout and stderr to the log file
        freopen(logURL.path, "a+", stdout)
        freopen(logURL.path, "a+", stderr)
        
        print("--- SuperSay Frontend Log Started: \(Date()) ---")
        
        // Create instances
        let audioInstance = AudioService()
        let historyInstance = HistoryManager()
        let pdfInstance = PDFService()
        let launchInstance = LaunchManager()
        let backendInstance = BackendService()
        let systemInstance = SystemService()
        
        // Create VM with dependency injection
        let vmInstance = DashboardViewModel(
            backend: backendInstance,
            system: systemInstance,
            audio: audioInstance,
            history: historyInstance
        )
        
        // Assign to StateObjects
        _audio = StateObject(wrappedValue: audioInstance)
        _history = StateObject(wrappedValue: historyInstance)
        _pdf = StateObject(wrappedValue: pdfInstance)
        _launchManager = StateObject(wrappedValue: launchInstance)
        _dashboardVM = StateObject(wrappedValue: vmInstance)
        
        self.backend = backendInstance
        
        systemInstance.requestPermissions()
        requestNotificationPermission()
        setupShortcuts(vm: vmInstance, audio: audioInstance)
        
        MetricsService.shared.trackLaunch()
        registerCustomFonts()
        checkRunningLocation()
    }
    
    private func checkRunningLocation() {
        let path = Bundle.main.bundlePath
        if path.contains("/Volumes/") {
            let alert = NSAlert()
            alert.messageText = "Move to Applications"
            alert.informativeText = "SuperSay needs to be in your Applications folder to work correctly. Would you like to move it now?"
            alert.addButton(withTitle: "Move to Applications")
            alert.addButton(withTitle: "Quit")
            
            if alert.runModal() == .alertFirstButtonReturn {
                // Open Applications folder so user can drag-and-drop
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                NSApplication.shared.terminate(nil)
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func registerCustomFonts() {
        guard let fontFolder = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else {
            print("📝 FontLoader: Could not locate Fonts directory in bundle.")
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontFolder, includingPropertiesForKeys: nil) else {
            print("📝 FontLoader: No bundled fonts found or directory inaccessible.")
            return
        }
        
        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                print("⚠️ FontLoader: Failed to register font at \(url.path): \(error?.takeRetainedValue().localizedDescription ?? "Unknown error")")
            } else {
                print("✅ FontLoader: Registered \(url.lastPathComponent)")
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    private func setupShortcuts(vm: DashboardViewModel, audio: AudioService) {
        print("⌨️ KeyboardShortcuts: Initializing registration...")
        
        KeyboardShortcuts.onKeyUp(for: .playText) {
            print("⌨️ KeyboardShortcuts: playText triggered")
            Task { @MainActor in
                await vm.speakSelection()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .togglePause) {
            print("⌨️ KeyboardShortcuts: togglePause triggered")
            Task { @MainActor in
                audio.togglePause()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .stopText) {
            print("⌨️ KeyboardShortcuts: stopText triggered")
            Task { @MainActor in
                audio.stop()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .exportAudio) {
            print("⌨️ KeyboardShortcuts: exportAudio triggered")
            Task { @MainActor in
                audio.exportToDesktop()
            }
        }
        
        print("⌨️ KeyboardShortcuts: All shortcuts registered.")
    }
    
    @AppStorage("showMenuBarIcon") var showMenuBarIcon = true
    
    var body: some Scene {
        WindowGroup(id: "dashboard") {
            SuperSayWindow()
                .environmentObject(dashboardVM)
                .environmentObject(audio)
                .environmentObject(history)
                .environmentObject(pdf)
                .environmentObject(launchManager)
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["dashboard"])
        
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            Button("Speak Selection") { Task { await dashboardVM.speakSelection() } }
            Button("Stop") { audio.stop() }
            Button("Quit") { 
                Task { await backend.stop() }
                NSApplication.shared.terminate(nil) 
            }
        } label: {
            Image("MenuBarIcon")
        }
    }
}
