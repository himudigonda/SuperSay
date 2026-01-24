import Foundation
import SwiftUI

class TelemetryService {
    static let shared = TelemetryService()
    
    @AppStorage("anonymousUserID") private var userID = UUID().uuidString
    @AppStorage("telemetryEnabled") private var enabled = true
    
    // Stats kept in UserDefaults
    @AppStorage("statAppLaunches") private var appLaunches = 0
    @AppStorage("statGenerations") private var generations = 0
    @AppStorage("statExports") private var exports = 0
    @AppStorage("statCharsProcessed") private var charsProcessed = 0
    
    // Mock Telemetry Endpoint (Replace with your actual analytics URL)
    private let endpoint = "https://api.supersay.app/v1/telemetry" 
    
    private init() {
        // Ensure userID is persistent
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
        
        // In a real app, you would POST to your endpoint here.
        // For now, we log to console so the user can see the "collection" happening.
        print("📊 Telemetry: [\(event)] user: \(userID.prefix(8))... data: \(metadata)")
        
        // Example native implementation:
        /*
        var payload = metadata
        payload["event"] = event
        payload["user_id"] = userID
        payload["platform"] = "macOS"
        payload["version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        
        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request).resume()
        */
    }
    
    // Helper for README/Stats display
    func getStatsSummary() -> String {
        return """
        --- SuperSay Stats ---
        Total Generations: \(generations)
        Characters Read: \(charsProcessed)
        Audio Exports: \(exports)
        -----------------------
        """
    }
}
