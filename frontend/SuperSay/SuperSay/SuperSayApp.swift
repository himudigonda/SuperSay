import SwiftUI

@main
struct SuperSayApp: App {
    // 1. Initialize Services
    private let backend = BackendService()
    private let system = SystemService()
    private let audio = AudioService()
    private let persistence = PersistenceService()
    private let launcher = LaunchService()
    
    // 2. Initialize ViewModels (StateObjects so they persist)
    @StateObject private var dashboardVM: DashboardViewModel
    @StateObject private var settingsVM = SettingsViewModel()
    
    init() {
        let vm = DashboardViewModel(
            backend: backend,
            system: system,
            audio: audio,
            persistence: persistence
        )
        _dashboardVM = StateObject(wrappedValue: vm)
    }
    
    var body: some Scene {
        // THE MAIN MEDIA APP
        WindowGroup(id: "dashboard") {
            // Update SuperSayWindow to take the VM instead of 'store'
            // For this phase, we inject the VM as an EnvironmentObject
            SuperSayWindow()
                .environmentObject(dashboardVM)
                // We inject 'audio' separately because some views might read it directly
                .environmentObject(audio) 
                .environmentObject(persistence)
                .environmentObject(settingsVM)
                .environmentObject(launcher)
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["dashboard"])
        
        // THE QUICK ACCESS MENU BAR (Native HUD)
        MenuBarExtra {
            Button("Speak Selection") { Task { await dashboardVM.speakSelection() } }
                // Global hotkey handled by KeyboardShortcuts
            
            Button("Stop Playback") { 
                dashboardVM.audio.stop()
                dashboardVM.status = .ready
            }
                // Global hotkey handled by KeyboardShortcuts

            Button(dashboardVM.audio.isPlaying ? "Pause" : "Resume") { dashboardVM.audio.togglePause() }
                .keyboardShortcut("/", modifiers: [.command, .shift])

            // Button("Export to Desktop") { Task { await dashboardVM.exportToDesktop() } }
            //    .keyboardShortcut("/", modifiers: [.control, .command, .shift])
            
            Divider()
            
            Button("Open Dashboard") {
                if let url = URL(string: "supersay://dashboard") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button("Quit") { 
                Task { await backend.stop() }
                NSApplication.shared.terminate(nil) 
            }
        } label: {
            HStack(spacing: 5) {
                // Dynamic Icon based on state
                switch dashboardVM.status {
                case .grabbing: Text("🔍")
                case .thinking: Text("🧠")
                case .speaking: Text("🗣️")
                case .paused:   Text("⏸️")
                case .error:    Text("⚠️")
                default:        Image(systemName: "waveform.circle.fill")
                }
                
                // Real-time progress in menu bar
                if dashboardVM.status == .speaking {
                    Text("\(Int(dashboardVM.audio.progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                }
            }
        }
    }
}
