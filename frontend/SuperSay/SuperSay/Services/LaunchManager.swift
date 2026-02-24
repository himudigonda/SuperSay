import Foundation
import Combine

import ServiceManagement

/// Handles the initial extraction and validation of the Python backend.
@MainActor
class LaunchManager: ObservableObject {
    @Published var isReady = false
    @Published var error: String? = nil
    
    // Fix: Add the actual registration logic
    @Published var isLaunchAtLoginEnabled: Bool = false {
        didSet {
            try? updateLoginItem()
        }
    }
    
    init() {
        // Sync the toggle state with macOS reality on start
        self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func updateLoginItem() throws {
        if isLaunchAtLoginEnabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
    
    func prepare() async {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.himudigonda.SuperSay"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID)
        
        // Target specifically the Server directory
        let serverURL = appSupport.appendingPathComponent("SuperSayServer")
        let executableURL = serverURL.appendingPathComponent("SuperSayServer")
        
        // 2. Extract
        guard let zipURL = Bundle.main.url(forResource: "SuperSayServer", withExtension: "zip") else {
            self.error = "Backend zip missing from bundle."
            return
        }
        
        do {
            // FIX: Only remove the server directory, PRESERVING LOGS
            if FileManager.default.fileExists(atPath: serverURL.path) {
                try FileManager.default.removeItem(at: serverURL)
            }
            
            // Ensure parent exists
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            // Unzip into appSupport (it creates SuperSayServer folder)
            unzip.arguments = ["-o", "-q", zipURL.path, "-d", appSupport.path]
            try unzip.run()
            unzip.waitUntilExit()
            
            // 3. Set permissions
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["755", executableURL.path]
            try chmod.run()
            chmod.waitUntilExit()
            
            self.isReady = true
        } catch {
            self.error = "Launch Error: \(error.localizedDescription)"
        }
    }
}
