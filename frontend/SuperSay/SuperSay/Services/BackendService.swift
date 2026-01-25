import Foundation
import Combine

actor BackendService {
    private var process: Process?
    private var isLaunching = false
    private let baseURL = URL(string: "http://127.0.0.1:10101")!
    
    // MARK: - Process Management
    
    func start() {
        guard process == nil && !isLaunching else { return }
        isLaunching = true
        guard let url = Bundle.main.url(forResource: "SuperSayServer", withExtension: nil) else {
            print("❌ Backend binary not found in Bundle!")
            return
        }
        
        let p = Process()
        p.executableURL = url
        
        // redirect to log file
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backend.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try? FileHandle(forWritingTo: logURL)
        logHandle?.seekToEndOfFile()
        
        p.standardOutput = logHandle
        p.standardError = logHandle
        
        do {
            try p.run()
            process = p
            print("✅ Backend Launched (PID: \(p.processIdentifier))")
            
            // Give it time to bind and load models
            Task {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                isLaunching = false
            }
        } catch {
            print("❌ Failed to launch backend: \(error)")
            isLaunching = false
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
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 10 // Increased for model loading
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isOnline = statusCode == 200
            if isOnline { 
                if isLaunching { print("📡 Backend is now Online") }
                isLaunching = false 
            }
            return isOnline
        } catch {
            // print("⚠️ Health Check Failed: \(error.localizedDescription)")
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
        
        print("📡 BackendService: POST /speak (\(text.count) chars)")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ BackendService: Invalid response type")
            throw URLError(.badServerResponse)
        }
        
        print("📡 BackendService: Received status \(httpResponse.statusCode), \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ BackendService: Server error \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }
        
        return data
    }
}
