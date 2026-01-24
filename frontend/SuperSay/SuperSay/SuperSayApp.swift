import SwiftUI

@main
struct SuperSayApp: App {
    // 1. Single Sources of Truth
    @StateObject private var audio = AudioService()
    @StateObject private var history = HistoryManager()
    @StateObject private var pdf = PDFService()
    @StateObject private var launchManager = LaunchManager()
    
    // 2. Logic Controller
    @StateObject private var dashboardVM: DashboardViewModel
    
    init() {
        // We create the dependencies first
        let _backend = BackendService()
        let _system = SystemService()
        let _audio = AudioService()
        let _history = HistoryManager()
        
        // We inject them into the VM
        let vm = DashboardViewModel(
            backend: _backend,
            system: _system,
            audio: _audio,
            history: _history
        )
        
        // We set the StateObjects
        _dashboardVM = StateObject(wrappedValue: vm)
        _audio = StateObject(wrappedValue: _audio)
        _history = StateObject(wrappedValue: _history)
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
                NSApplication.shared.terminate(nil) 
            }
        } label: {
            Image(systemName: "waveform.circle.fill")
        }
    }
}
