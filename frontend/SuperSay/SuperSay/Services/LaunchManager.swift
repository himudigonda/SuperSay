import Combine
import Foundation
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
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
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
        let fm = FileManager.default
        let bundleID = Bundle.main.bundleIdentifier ?? "com.himudigonda.SuperSay"
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID)

        let serverURL    = appSupport.appendingPathComponent("SuperSayServer")
        let executableURL = serverURL.appendingPathComponent("SuperSayServer")
        // Marker file: stores the bundle version that was last extracted.
        let versionMarkerURL = serverURL.appendingPathComponent(".bundle_version")

        guard let zipURL = Bundle.main.url(forResource: "SuperSayServer", withExtension: "zip") else {
            error = "Backend zip missing from bundle."
            return
        }

        // ─── Fast path: skip the 60-120 s zip extraction when binary is already current ───
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown"
        if fm.isExecutableFile(atPath: executableURL.path),
           let stored = try? String(contentsOf: versionMarkerURL, encoding: .utf8),
           stored.trimmingCharacters(in: .whitespacesAndNewlines) == currentVersion {
            print("✅ Backend v\(currentVersion) already extracted — skipping unzip.")
            isReady = true
            return
        }

        // ─── Slow path: extract (first launch or after an app update) ───────────────────
        print("📦 Extracting backend v\(currentVersion)… (first launch or update)")
        do {
            // Remove stale server dir only; logs live in the parent appSupport dir.
            if fm.fileExists(atPath: serverURL.path) {
                try fm.removeItem(at: serverURL)
            }
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", "-q", zipURL.path, "-d", appSupport.path]
            try unzip.run()
            unzip.waitUntilExit()

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["755", executableURL.path]
            try chmod.run()
            chmod.waitUntilExit()

            // Stamp version so the next launch takes the fast path.
            try currentVersion.write(to: versionMarkerURL, atomically: true, encoding: .utf8)

            print("✅ Backend extracted successfully.")
            isReady = true
        } catch {
            self.error = "Launch Error: \(error.localizedDescription)"
        }
    }
}
