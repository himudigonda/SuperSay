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
        self.isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
    
    private func updateLoginItem() {
        do {
            if isLaunchAtLoginEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}
