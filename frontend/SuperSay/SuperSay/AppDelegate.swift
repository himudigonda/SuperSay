import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Synchronous SIGKILL of any lingering SuperSayServer processes
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-9", "-f", "SuperSayServer"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Silently ignore if pkill fails (process may not exist)
            return
        }
    }
}
