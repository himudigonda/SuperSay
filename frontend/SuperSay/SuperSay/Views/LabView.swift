import SwiftUI

struct LabView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @EnvironmentObject var launchManager: LaunchManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("The Lab").font(.system(size: 30, weight: .bold, design: .rounded))
                
                GroupBox(label: Label("Audio Environment", systemImage: "speaker.wave.3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Duck Music Volume", isOn: $vm.enableDucking)
                        Toggle("Clean URLs from Text", isOn: $vm.cleanURLs)
                    }
                }
                
                GroupBox(label: Label("Voice & Speed", systemImage: "tuningfork")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Voice", selection: $vm.selectedVoice) {
                            Text("🇺🇸 Bella").tag("af_bella")
                            Text("🇺🇸 Sarah").tag("af_sarah")
                            Text("🇺🇸 Adam").tag("am_adam")
                            Text("🇺🇸 Michael").tag("am_michael")
                            Text("🇬🇧 Emma").tag("bf_emma")
                            Text("🇬🇧 Isabella").tag("bf_isabella")
                            Text("🇬🇧 George").tag("bm_george")
                            Text("🇬🇧 Lewis").tag("bm_lewis")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Speed: \(String(format: "%.1f", vm.speechSpeed))x").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $vm.speechSpeed, in: 0.5...2.0)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Volume").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $vm.speechVolume, in: 0.0...1.5)
                        }
                    }
                }
                
                GroupBox(label: Label("System", systemImage: "macpro.gen3")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Appearance", selection: $vm.appTheme) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }.pickerStyle(.segmented)
                        
                        Toggle("Start at Login", isOn: $launchManager.isLaunchAtLoginEnabled)
                    }
                }
            }
            .padding(30)
        }
    }
}
