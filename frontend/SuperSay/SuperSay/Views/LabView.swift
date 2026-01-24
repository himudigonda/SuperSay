import SwiftUI

struct LabView: View {
    @EnvironmentObject var vm: DashboardViewModel
    @EnvironmentObject var launchManager: LaunchManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("The Lab").font(.system(size: 30, weight: .bold, design: .rounded))
                
                GroupBox(label: Label("Audio Environment", systemImage: "speaker.wave.3")) {
                    Toggle("Duck Music Volume", isOn: $vm.enableDucking)
                }
                
                GroupBox(label: Label("Voice & Speed", systemImage: "tuningfork")) {
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
                    Slider(value: $vm.speechSpeed, in: 0.5...2.0)
                    Slider(value: $vm.speechVolume, in: 0.0...1.5)
                }
                
                GroupBox(label: Label("System", systemImage: "macpro.gen3")) {
                    Toggle("Start at Login", isOn: $launchManager.isLaunchAtLoginEnabled)
                }
            }
            .padding(30)
        }
    }
}
