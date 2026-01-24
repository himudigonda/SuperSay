import SwiftUI

struct LabView: View {
    @EnvironmentObject var store: SuperSayStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("The Lab").font(.system(size: 30, weight: .bold, design: .rounded))
                
                // AUDIO SETTINGS
                GroupBox(label: Label("Audio Environment", systemImage: "speaker.wave.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Duck Music Volume", isOn: $store.enableDucking)
                        Text("Lowers Music/Spotify volume while speaking.").font(.caption).foregroundStyle(.secondary)
                        
                        Divider().padding(.vertical, 5)
                        
                        Toggle("Show Notifications", isOn: $store.showNotifications)
                    }
                    .padding(8)
                }
                
                // TEXT PROCESSING
                GroupBox(label: Label("Text Intelligence", systemImage: "brain")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Clean URLs", isOn: $store.cleanURLs)
                        Toggle("Fix PDF Formatting", isOn: $store.fixLigatures)
                        
                        Divider().padding(.vertical, 5)
                        
                        HStack {
                            Image(systemName: "globe")
                                .foregroundStyle(.secondary)
                            Text("Automatic Language Detection")
                                .font(.subheadline)
                            Spacer()
                            Text("Enabled")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    .padding(8)
                }
                
                // VOICE CALIBRATION
                GroupBox(label: Label("Voice & Speed", systemImage: "tuningfork")) {
                    VStack(alignment: .leading, spacing: 15) {
                        Picker("Voice", selection: $store.selectedVoice) {
                            Section("American") {
                                Text("🇺🇸 Bella").tag("af_bella")
                                Text("🇺🇸 Sarah").tag("af_sarah")
                                Text("🇺🇸 Adam").tag("am_adam")
                                Text("🇺🇸 Michael").tag("am_michael")
                            }
                            Section("British") {
                                Text("🇬🇧 Emma").tag("bf_emma")
                                Text("🇬🇧 Isabella").tag("bf_isabella")
                                Text("🇬🇧 George").tag("bm_george")
                                Text("🇬🇧 Lewis").tag("bm_lewis")
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Speed: \(String(format: "%.1f", store.speechSpeed))x")
                            Slider(value: $store.speechSpeed, in: 0.5...2.0, step: 0.1)
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Volume: \(Int(store.speechVolume * 100))%")
                            Slider(value: $store.speechVolume, in: 0.0...1.5, step: 0.1)
                            if store.speechVolume > 1.0 {
                                Text("⚠️ Digital boost may cause distortion")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(8)
                }
                
                // SYSTEM
                GroupBox(label: Label("System", systemImage: "macpro.gen3")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Start at Login", isOn: $store.launchManager.isLaunchAtLoginEnabled)
                        
                        Picker("Theme", selection: $store.appTheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }.pickerStyle(.segmented)
                        
                        Divider().padding(.vertical, 5)
                        
                        Button(role: .destructive) {
                            store.resetSystemPermissions()
                        } label: {
                            Label("Reset Permissions", systemImage: "arrow.counterclockwise")
                        }
                    }
                    .padding(8)
                }
                
                // FOOTER
                VStack(alignment: .center, spacing: 8) {
                    Divider().padding(.vertical, 10)
                    
                    Text("SuperSay v1.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("Developed by")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Link("Himansh Mudigonda", destination: URL(string: "https://github.com/himudigonda")!)
                            .font(.caption2)
                    }
                    
                    HStack(spacing: 16) {
                        Link(destination: URL(string: "https://github.com/himudigonda")!) {
                            Image("github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        
                        Link(destination: URL(string: "https://linkedin.com/in/himudigonda")!) {
                            Image("linkedin")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(30)
        }
    }
}
