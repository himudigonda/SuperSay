import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    /// A restored AppKit frame can be smaller than SwiftUI's content frame.
    /// Enforce the dashboard's viable minimum on the window itself so the
    /// navigation list and migration footer cannot collapse into each other.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.enforceDashboardMinimumSize()
        }
    }

    private func enforceDashboardMinimumSize() {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }

        let minimum = NSSize(width: 800, height: 600)
        window.minSize = minimum

        var frame = window.frame
        frame.size.width = max(frame.size.width, minimum.width)
        frame.size.height = max(frame.size.height, minimum.height)
        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
    }
}
