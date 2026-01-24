import Foundation
import ServiceManagement
import Combine

class LaunchManager: ObservableObject {
    @Published var isLaunchAtLoginEnabled: Bool {
        didSet {
            toggleLaunchAtLogin()
        }
    }
    
    init() {
        // Check current status
        self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    print("✅ [Launch] Registered for login")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    print("🚫 [Launch] Unregistered from login")
                }
            }
        } catch {
            print("⚠️ [Launch] Failed to update login status: \(error.localizedDescription)")
        }
    }
}
