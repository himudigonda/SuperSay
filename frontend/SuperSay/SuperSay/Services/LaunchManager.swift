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
        let executableURL = appSupport.appendingPathComponent("SuperSayServer/SuperSayServer")
        
        // 1. If binary exists, we are potentially ready
        if FileManager.default.fileExists(atPath: executableURL.path) {
            self.isReady = true
            return
        }
        
        // 2. Extract
        guard let zipURL = Bundle.main.url(forResource: "SuperSayServer", withExtension: "zip") else {
            self.error = "Backend zip missing from bundle."
            return
        }
        
        do {
            // --- FIX: Force Refresh ---
            // We delete the old backend folder to ensure the new ZIP is always extracted.
            // This prevents "sticky" broken builds from persisting in Application Support.
            if FileManager.default.fileExists(atPath: appSupport.path) {
                try FileManager.default.removeItem(at: appSupport)
            }
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", "-q", zipURL.path, "-d", appSupport.path]
            try unzip.run()
            unzip.waitUntilExit()
            
            // 3. CRITICAL: Set permissions immediately after unzip
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
