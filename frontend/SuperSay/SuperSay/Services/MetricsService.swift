import Foundation
import SwiftUI

class MetricsService {
    static let shared = MetricsService()

    // Retrieve ID/Enabled state from AppStorage
    @AppStorage("anonymousUserID") private var userID = UUID().uuidString
    @AppStorage("telemetryEnabled") private var enabled = true

    /// Use your website's endpoint
    private let endpoint = "https://himudigonda.me/api/telemetry"

    private init() {
        // Ensure the ID is set if it somehow got cleared
        if userID.isEmpty { userID = UUID().uuidString }
    }

    // --- Public Tracking Methods (called by VM/AudioService) ---

    func trackLaunch() {
        sendMetric(event: "app_launch")
    }

    func trackGeneration(charCount: Int) {
        sendMetric(event: "generation", metadata: ["chars": charCount])
    }

    func trackExport() {
        sendMetric(event: "export")
    }

    // --- Core Logic ---

    private func sendMetric(event: String, metadata: [String: Any] = [:]) {
        guard enabled else { return }

        let payload: [String: Any] = [
            "event": event,
            "user_id": userID,
            "platform": "macOS",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "app_name": "SuperSay",
            "metadata": metadata,
        ]

        guard let url = URL(string: endpoint) else {
            print("❌ Metrics Failed: Invalid endpoint URL '\(endpoint)'.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request).resume()
        print("📡 Metrics: [\(event)] sent to himudigonda.me")
    }
}
