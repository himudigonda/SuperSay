import Foundation
import Combine

actor BackendService: NSObject, URLSessionDataDelegate {
    private var process: Process?
    private var isLaunching = false
    private let baseURL = URL(string: "http://127.0.0.1:10101")!
    
    // Streaming state
    private var continuation: AsyncStream<Data>.Continuation?
    
    // MARK: - Process Management
    
    func start() {
        guard process == nil && !isLaunching else { return }
        isLaunching = true
        guard let url = Bundle.main.url(forResource: "SuperSayServer", withExtension: nil) else {
            print("❌ Backend binary not found in Bundle!")
            return
        }
        
        // Check if already running (pkill cleanup)
        let cleanup = Process()
        cleanup.launchPath = "/usr/bin/pkill"
        cleanup.arguments = ["-f", "SuperSayServer"]
        try? cleanup.run()
        cleanup.waitUntilExit()
        
        let p = Process()
        p.executableURL = url
        
        // FIX: Force Python to unbuffer output so logs appear immediately
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        
        // redirect to log file
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backend.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        
        // Truncate file to start fresh for this session
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        
        let logHandle = try? FileHandle(forWritingTo: logURL)
        
        p.standardOutput = logHandle
        p.standardError = logHandle
        
        do {
            try p.run()
            process = p
            print("✅ Backend Launched (PID: \(p.processIdentifier))")
            
            // Give it time to bind and load models
            Task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
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
        task.arguments = ["-9", "-f", "SuperSayServer"]
        try? task.run()
    }
    
    func exportLogs() {
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backend.log")
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].appendingPathComponent("SuperSay_Backend_Log.txt")
        
        do {
            if FileManager.default.fileExists(atPath: desktop.path) {
                try FileManager.default.removeItem(at: desktop)
            }
            try FileManager.default.copyItem(at: logURL, to: desktop)
            print("✅ Backend Logs exported to Desktop")
        } catch {
            print("❌ Failed to export logs: \(error)")
        }
    }
    
    // MARK: - API
    
    func checkHealth() async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            // Check if backend is in "Initializing" state (model loading)
            if statusCode == 503 {
                print("📡 Backend: Still loading models...")
                return false
            }
            
            let isOnline = statusCode == 200
            if isOnline && isLaunching { 
                print("📡 Backend is now Online")
                isLaunching = false 
            }
            return isOnline
        } catch {
            return false
        }
    }
    
    // MARK: - Streaming API
    
    func streamAudio(text: String, voice: String, speed: Double, volume: Double) -> AsyncStream<Data> {
        return AsyncStream { continuation in
            self.continuation = continuation
            
            let url = baseURL.appendingPathComponent("speak")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60
            
            let payload: [String: Any] = [
                "text": text,
                "voice": voice,
                "speed": speed,
                "volume": volume
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                print("📡 BackendService: Starting stream for \(text.count) chars")
                
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                task.resume()
                
            } catch {
                print("❌ BackendService: Failed to create request: \(error)")
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                // Task was cancelled or finished
            }
        }
    }
    
    // MARK: - URLSessionDataDelegate
    
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            await self.handleIncomingData(data)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            if let error = error {
                print("❌ BackendService: Stream error: \(error.localizedDescription)")
            } else {
                print("✅ BackendService: Stream finished successfully")
            }
            await self.finishStream()
        }
    }
    
    private func handleIncomingData(_ data: Data) {
        continuation?.yield(data)
    }
    
    private func finishStream() {
        continuation?.finish()
        continuation = nil
    }
}
