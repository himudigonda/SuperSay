import SwiftUI
import KeyboardShortcuts

struct PreferencesView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @EnvironmentObject var audio: AudioService
    @EnvironmentObject var launchManager: LaunchManager
    
    @AppStorage("showMenuBarIcon") var showMenuBarIcon = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferences")
                        .font(vm.appFont(size: 34, weight: .bold))
                    Text("Configure SuperSay to match your workflow.")
                        .font(vm.appFont(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                
                // Section: Voice Engine
                PreferenceSection(title: "Voice Engine", icon: "cpu") {
                    VStack(spacing: 20) {
                        HStack {
                            Label("Active Voice", systemImage: "person.wave.2")
                                .font(vm.appFont(size: 14))
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
                                    .font(vm.appFont(size: 14))
                                Spacer()
                                Text("\(String(format: "%.1f", vm.speechSpeed))x")
                                    .font(vm.appFont(size: 14, weight: .bold).monospaced())
                                    .foregroundStyle(.cyan)
                                    .fontWeight(.bold)
                            }
                            Slider(value: $vm.speechSpeed, in: 0.5...2.0)
                                .tint(.cyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Master Volume", systemImage: "speaker.wave.3")
                                    .font(vm.appFont(size: 14))
                                Spacer()
                                Text("\(Int(vm.speechVolume * 100))%")
                                    .font(vm.appFont(size: 14, weight: .bold).monospaced())
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
                                    .font(vm.appFont(size: 16))
                                Text("Attenuates background music while SuperSay is speaking.")
                                    .font(vm.appFont(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $vm.cleanURLs) {
                            VStack(alignment: .leading) {
                                Text("Sanitize URLs")
                                    .font(vm.appFont(size: 16))
                                Text("Automatically removes complex URLs and handles from spoken text.")
                                    .font(vm.appFont(size: 12))
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
                                .font(vm.appFont(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Reset to Defaults") {
                                resetShortcuts()
                            }
                            .buttonStyle(.borderless)
                            .font(vm.appFont(size: 12))
                            .foregroundStyle(.red)
                        }
                    }
                }
                
                // Section: System & Appearance
                PreferenceSection(title: "Application", icon: "window.badge.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Theme")
                                .font(vm.appFont(size: 14))
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
                        
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Typography")
                                    .font(vm.appFont(size: 14, weight: .bold))
                                Text("Current: \(vm.selectedFontName)")
                                    .font(vm.appFont(size: 11))
                                    .foregroundStyle(.cyan)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 12) {
                                Picker("", selection: $vm.selectedFontName) {
                                    Text("System Rounded").tag("System Rounded")
                                    Text("System Standard").tag("System Standard")
                                    Text("System Mono").tag("System Mono")
                                    Text("System Serif").tag("System Serif")
                                    Divider()
                                    Text("Poppins").tag("Poppins")
                                }
                                .frame(width: 200)
                                
                                Button {
                                    vm.showFontPanel()
                                } label: {
                                    Label("More Fonts...", systemImage: "textformat.size")
                                        .font(vm.appFont(size: 11, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $launchManager.isLaunchAtLoginEnabled) {
                            Text("Start at Login")
                                .font(vm.appFont(size: 14))
                        }
                        .toggleStyle(.switch)
                        
                        Divider()
                        
                        Toggle(isOn: $showMenuBarIcon) {
                            Text("Show Menu Bar Icon")
                                .font(vm.appFont(size: 14))
                        }
                        .toggleStyle(.switch)
                        
                        Divider()
                        
                         Toggle(isOn: $vm.telemetryEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Anonymous Analytics")
                                    .font(vm.appFont(size: 14, weight: .bold))
                                Text("Help improve SuperSay by sharing anonymous usage statistics with himudigonda.me")
                                    .font(vm.appFont(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .help("We collect: App Launches, Character Counts, and Export Counts. No text content or personal data is ever recorded or transmitted.")
                        
                        Divider()

                        HStack {
                            Button {
                                vm.checkForUpdates()
                            } label: {
                                Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
                                    .font(vm.appFont(size: 13, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"))
                                .font(vm.appFont(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        Button {
                            audio.exportToDesktop()
                        } label: {
                            Label("Export Last Clip to Desktop", systemImage: "square.and.arrow.down")
                                .font(vm.appFont(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .help("Manually export the most recently generated audio clip.")
                        
                        Button {
                            vm.exportLogs()
                        } label: {
                            Label("Export Debug Logs", systemImage: "doc.text.fill")
                                .font(vm.appFont(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .help("Save backend usage logs to Desktop for troubleshooting.")
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
    @EnvironmentObject var vm: DashboardViewModel
    let title: String
    let name: KeyboardShortcuts.Name
    
    var body: some View {
        HStack {
            Text(title)
                .font(vm.appFont(size: 14, weight: .medium))
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
        }
    }
}

struct PreferenceSection<Content: View>: View {
    @EnvironmentObject var vm: DashboardViewModel
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
                    .font(vm.appFont(size: 13, weight: .bold))
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
