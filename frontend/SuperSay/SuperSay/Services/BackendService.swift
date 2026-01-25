import Foundation
import Combine

actor BackendService: NSObject, URLSessionDataDelegate {
    private var process: Process?
    public var isLaunching = false
    private let baseURL = URL(string: "http://127.0.0.1:10101")!
    
    // Streaming state
    private var continuations: [Int: AsyncStream<Data>.Continuation] = [:]
    
    // MARK: - Process Management
    
    func start() {
        guard process == nil && !isLaunching else { return }
        isLaunching = true
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backendFolder = appSupport.appendingPathComponent("SuperSayServer")
        let executableURL = backendFolder.appendingPathComponent("SuperSayServer")
        
        if !FileManager.default.fileExists(atPath: executableURL.path) {
            print("📦 BackendService: Installing backend engine...")
            self.log(message: "📦 Installing backend engine...")
            
            guard let zipURL = Bundle.main.url(forResource: "SuperSayServer", withExtension: "zip") else {
                print("❌ Backend ZIP not found in Bundle!")
                self.log(message: "❌ Backend ZIP not found")
                isLaunching = false
                return
            }
            
            do {
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", "-q", zipURL.path, "-d", appSupport.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()
                print("✅ Backend installed to: \(backendFolder.path)")
            } catch {
                print("❌ Failed to unzip backend: \(error)")
                self.log(message: "❌ Failed to unzip backend: \(error)")
                isLaunching = false
                return
            }
        }
        
        let cleanup = Process()
        cleanup.launchPath = "/usr/bin/pkill"
        cleanup.arguments = ["-f", "SuperSayServer"]
        try? cleanup.run()
        cleanup.waitUntilExit()
        
        let p = Process()
        p.executableURL = executableURL
        
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        
        let logURL = appSupport.appendingPathComponent("backend.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                try? FileHandle(forWritingTo: logURL).seekToEndOfFile()
                try? FileHandle(forWritingTo: logURL).write(contentsOf: data)
                try? FileHandle(forWritingTo: logURL).closeFile()
                print("[BACKEND] \(str)")
            }
        }
        
        do {
            try p.run()
            process = p
            print("✅ Backend Launched (PID: \(p.processIdentifier))")
            
            Task {
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                isLaunching = false
            }
        } catch {
            print("❌ Failed to launch backend: \(error)")
            self.log(message: "❌ Failed to launch backend: \(error)")
            isLaunching = false
        }
    }
    
    private func log(message: String) {
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backend.log")
        let entry = "\(Date()): \(message)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
    
    func stop() {
        process?.terminate()
        process = nil
        
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
    
    func checkHealth() async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            
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
                
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                
                let id = Int.random(in: 1...Int.max)
                task.taskDescription = "\(id)"
                self.continuations[id] = continuation
                
                task.resume()
                
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                    Task { [id] in
                        await self.removeContinuation(id: id)
                    }
                }
            } catch {
                print("❌ BackendService: Failed to create request: \(error)")
                continuation.finish()
            }
        }
    }
    
    private func removeContinuation(id: Int) {
        continuations.removeValue(forKey: id)
    }
    
    // MARK: - URLSessionDataDelegate
    
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let idString = dataTask.taskDescription, let id = Int(idString) else { return }
        Task {
            await self.yieldData(id: id, data: data)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let idString = task.taskDescription, let id = Int(idString) else { return }
        Task {
            if let error = error {
                print("❌ BackendService: Stream \(id) error: \(error.localizedDescription)")
            }
            await self.finishContinuation(id: id)
        }
    }
    
    private func yieldData(id: Int, data: Data) {
        continuations[id]?.yield(data)
    }
    
    private func finishContinuation(id: Int) {
        continuations[id]?.finish()
        continuations.removeValue(forKey: id)
    }
}
