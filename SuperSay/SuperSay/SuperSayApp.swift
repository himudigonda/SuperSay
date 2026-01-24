import SwiftUI

@main
struct SuperSayApp: App {
    @StateObject private var store = SuperSayStore()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        // THE MAIN MEDIA APP
        WindowGroup(id: "dashboard") {
            SuperSayWindow()
                .environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: ["dashboard"])
        
        // THE QUICK ACCESS MENU BAR (Native HUD)
        MenuBarExtra {
            Button("Speak Selection") { Task { await store.speakSelection() } }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            
            Button("Stop Playback") { 
                store.audio.stop()
                store.status = .ready
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])

            Button(store.audio.isPlaying ? "Pause" : "Resume") { store.audio.togglePause() }
                .keyboardShortcut("/", modifiers: [.command, .shift])

            Button("Export to Desktop") { Task { await store.exportToDesktop() } }
                .keyboardShortcut("/", modifiers: [.control, .command, .shift])
            
            Divider()
            
            Button("Open Dashboard") {
                if let url = URL(string: "supersay://dashboard") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button("Quit") { 
                store.stopBackend()
                NSApplication.shared.terminate(nil) 
            }
        } label: {
            HStack(spacing: 5) {
                // Dynamic Icon based on state
                switch store.status {
                case .grabbing: Text("🔍")
                case .thinking: Text("🧠")
                case .speaking: Text("🗣️")
                case .paused:   Text("⏸️")
                case .error:    Text("⚠️")
                default:        Image(systemName: "waveform.circle.fill")
                }
                
                // Real-time progress in menu bar
                if store.status == .speaking {
                    Text("\(Int(store.audio.progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                }
            }
        }
    }
}
