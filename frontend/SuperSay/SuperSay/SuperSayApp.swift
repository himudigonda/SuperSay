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
        
        TelemetryService.shared.trackLaunch()
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
        
        MenuBarExtra {
            Button("Speak Selection") { Task { await dashboardVM.speakSelection() } }
            Button("Stop") { audio.stop() }
            Button("Quit") { 
                Task { await backend.stop() }
                NSApplication.shared.terminate(nil) 
            }
        } label: {
            Image(systemName: "waveform.circle.fill")
        }
    }
}
