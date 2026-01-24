import Foundation
import SwiftUI

class TelemetryService {
    static let shared = TelemetryService()
    
    @AppStorage("anonymousUserID") private var userID = UUID().uuidString
    @AppStorage("telemetryEnabled") private var enabled = true
    
    // Stats kept in UserDefaults (Keep these local for persistence)
    @AppStorage("statAppLaunches") private var appLaunches = 0
    @AppStorage("statGenerations") private var generations = 0
    @AppStorage("statExports") private var exports = 0
    @AppStorage("statCharsProcessed") private var charsProcessed = 0
    
    // --- TARGET IS YOUR WEBSITE ---
    private let endpoint = "https://himudigonda.me/api/telemetry"
    
    private init() {
        if userID.isEmpty { userID = UUID().uuidString }
    }
    
    func trackLaunch() {
        appLaunches += 1
        sendTelemetry(event: "app_launch")
    }
    
    func trackGeneration(charCount: Int) {
        generations += 1
        charsProcessed += charCount
        sendTelemetry(event: "generation", metadata: ["chars": charCount])
    }
    
    func trackExport() {
        exports += 1
        sendTelemetry(event: "export")
    }
    
    private func sendTelemetry(event: String, metadata: [String: Any] = [:]) {
        guard enabled else { return }
        
        // Prepare payload with global context
        let payload: [String: Any] = [
            "event": event,
            "user_id": userID,
            "platform": "macOS",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "metadata": metadata
        ]
        
        guard let url = URL(string: endpoint) else { 
            print("❌ Telemetry Failed: Invalid endpoint URL.")
            return 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        // Send asynchronously
        URLSession.shared.dataTask(with: request).resume()
        print("📊 Telemetry: [\(event)] sent to himudigonda.me")
    }
    
    func getStatsSummary() -> String {
        return """
        --- SuperSay Stats (Local Counter) ---
        Total Generations: \(generations)
        Characters Read: \(charsProcessed)
        Audio Exports: \(exports)
        -------------------------------------
        """
    }
}
