import SwiftUI

class SettingsViewModel: ObservableObject {
    @AppStorage("selectedVoice") var selectedVoice = "af_bella"
    @AppStorage("speechSpeed") var speechSpeed = 1.0
    @AppStorage("speechVolume") var speechVolume = 1.0
    @AppStorage("enableDucking") var enableDucking = true
    @AppStorage("appTheme") var appTheme = "system" // system, light, dark
    
    private let system: SystemService?
    
    init(system: SystemService? = nil) {
        self.system = system
    }
    
    // Potentially add logic to preview voice or reset settings
    
    func resetToDefaults() {
        selectedVoice = "af_bella"
        speechSpeed = 1.0
        speechVolume = 1.0
        enableDucking = true
        cleanURLs = true
        appTheme = "system"
    }
    
    func resetSystemPermissions() {
        // This is a bit of a hack since SystemService was just a wrapper.
        // We can just call tccutil here or via SystemService.
        // If SystemService is injected, use it?
        // Actually SystemService in my implementation had setMusicVolume and requestPermissions.
        // It didn't have reset.
        // Let's implement a shell call here or assume SystemService needs update.
        // For now, let's keep it simple.
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.himudigonda.SuperSay"]
        try? task.run()
    }
}
