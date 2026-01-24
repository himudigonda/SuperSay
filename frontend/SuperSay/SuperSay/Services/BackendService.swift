import Foundation
import Combine

actor BackendService {
    private var process: Process?
    private let baseURL = URL(string: "http://127.0.0.1:8000")!
    
    // MARK: - Process Management
    
    func start() {
        guard process == nil else { return }
        guard let url = Bundle.main.url(forResource: "SuperSayServer", withExtension: nil) else {
            print("❌ Backend binary not found in Bundle!")
            return
        }
        
        let p = Process()
        p.executableURL = url
        p.standardOutput = FileHandle.nullDevice // Redirect to null to prevent buffer clogging
        p.standardError = FileHandle.standardError
        
        do {
            try p.run()
            process = p
            print("✅ Backend Launched")
        } catch {
            print("❌ Failed to launch backend: \(error)")
        }
    }
    
    func stop() {
        process?.terminate()
        process = nil
        
        // Force kill to be safe
        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-9", "SuperSayServer"]
        try? task.run()
    }
    
    // MARK: - API
    
    func checkHealth() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    func generateAudio(text: String, voice: String, speed: Double, volume: Double) async throws -> Data {
        let url = baseURL.appendingPathComponent("speak")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // Long timeout for long text
        
        let payload: [String: Any] = [
            "text": text,
            "voice": voice,
            "speed": speed,
            "volume": volume
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
}
