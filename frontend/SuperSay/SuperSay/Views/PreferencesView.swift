import SwiftUI
import KeyboardShortcuts

struct PreferencesView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var launchManager: LaunchManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferences")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Configure SuperSay to match your workflow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                
                // Section: Voice Engine
                PreferenceSection(title: "Voice Engine", icon: "cpu") {
                    VStack(spacing: 20) {
                        HStack {
                            Label("Active Voice", systemImage: "person.wave.2")
                            Spacer()
                            Picker("", selection: $vm.selectedVoice) {
                                Group {
                                    Text("🇺🇸 Bella").tag("af_bella")
                                    Text("🇺🇸 Sarah").tag("af_sarah")
                                    Text("🇺🇸 Adam").tag("am_adam")
                                    Text("🇺🇸 Michael").tag("am_michael")
                                }
                                Divider()
                                Group {
                                    Text("🇬🇧 Emma").tag("bf_emma")
                                    Text("🇬🇧 Isabella").tag("bf_isabella")
                                    Text("🇬🇧 George").tag("bm_george")
                                    Text("🇬🇧 Lewis").tag("bm_lewis")
                                }
                            }
                            .frame(width: 150)
                            .labelsHidden()
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Speech Speed", systemImage: "gauge.with.needle")
                                Spacer()
                                Text("\(String(format: "%.1f", vm.speechSpeed))x")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.cyan)
                                    .fontWeight(.bold)
                            }
                            Slider(value: $vm.speechSpeed, in: 0.5...2.0)
                                .tint(.cyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Master Volume", systemImage: "speaker.wave.3")
                                Spacer()
                                Text("\(Int(vm.speechVolume * 100))%")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.cyan)
                                    .fontWeight(.bold)
                            }
                            Slider(value: $vm.speechVolume, in: 0.0...1.5)
                                .tint(.cyan)
                        }
                    }
                }
                
                // Section: Audio Environment
                PreferenceSection(title: "Audio Environment", icon: "hifispeaker") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $vm.enableDucking) {
                            VStack(alignment: .leading) {
                                Text("Music Ducking")
                                Text("Attenuates background music while SuperSay is speaking.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $vm.cleanURLs) {
                            VStack(alignment: .leading) {
                                Text("Sanitize URLs")
                                Text("Automatically removes complex URLs and handles from spoken text.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Section: Keyboard Shortcuts
                PreferenceSection(title: "Shortcuts", icon: "keyboard") {
                    VStack(spacing: 0) {
                        ShortcutRow(title: "Speak Selection", name: .playText)
                        Divider().padding(.vertical, 8)
                        ShortcutRow(title: "Pause / Resume", name: .togglePause)
                        Divider().padding(.vertical, 8)
                        ShortcutRow(title: "Stop Playback", name: .stopText)
                        Divider().padding(.vertical, 8)
                        ShortcutRow(title: "Export to Desktop", name: .exportAudio)
                        
                        Divider().padding(.vertical, 16)
                        
                        HStack {
                            Text("Shortcuts are global and work from any app.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Reset to Defaults") {
                                resetShortcuts()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                    }
                }
                
                // Section: System & Appearance
                PreferenceSection(title: "Application", icon: "window.badge.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Theme")
                            Spacer()
                            Picker("", selection: $vm.appTheme) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                        
                        Divider()
                        
                        Toggle("Start at Login", isOn: $launchManager.isLaunchAtLoginEnabled)
                            .toggleStyle(.switch)
                        
                        Divider()
                        
                        Toggle(isOn: $vm.telemetryEnabled) {
                            VStack(alignment: .leading) {
                                Text("Anonymous Analytics")
                                Text("Help improve SuperSay by sharing anonymous usage statistics with himudigonda.me")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .help("We collect: App Launches, Character Counts, and Export Counts. No text content or personal data is ever recorded or transmitted.")
                        
                        Divider()
                        
                        Button {
                            audio.exportToDesktop()
                        } label: {
                            Label("Export Last Clip to Desktop", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .help("Manually export the most recently generated audio clip.")
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: 800)
        }
    }
    
    private func resetShortcuts() {
        for name in KeyboardShortcuts.Name.allCases {
            KeyboardShortcuts.reset(name)
        }
    }
}

struct ShortcutRow: View {
    let title: String
    let name: KeyboardShortcuts.Name
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .fontWeight(.medium)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
                .font(.body)
        }
    }
}

struct PreferenceSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                    .font(.headline)
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
            }
            
            VStack {
                content
            }
            .padding(20)
            .background(.ultraThinMaterial.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
