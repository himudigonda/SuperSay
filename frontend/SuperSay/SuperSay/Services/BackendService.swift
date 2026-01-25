import Foundation
import Combine

final class BackendService: NSObject {
    private var process: Process?
    private(set) var isLaunching = false
    private let baseURL = URL(string: "http://127.0.0.1:10101")!
    
    // Thread-safe state
    private let lock = NSRecursiveLock()
    private var continuations: [Int: AsyncStream<Data>.Continuation] = [:]
    
    // Shared session for streaming
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // MARK: - Process Management
    
    func start() {
        lock.lock()
        defer { lock.unlock() }
        
        guard process == nil && !isLaunching else { return }
        isLaunching = true
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backendFolder = appSupport.appendingPathComponent("SuperSayServer")
        let executableURL = backendFolder.appendingPathComponent("SuperSayServer")
        
        if !FileManager.default.fileExists(atPath: executableURL.path) {
            print("📦 BackendService: Installing backend engine...")
            
            guard let zipURL = Bundle.main.url(forResource: "SuperSayServer", withExtension: "zip") else {
                print("❌ Backend ZIP not found in Bundle!")
                isLaunching = false
                return
            }
            
            do {
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", "-q", zipURL.path, "-d", appSupport.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()
            } catch {
                print("❌ Failed to unzip backend: \(error)")
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
        
        _ = try? "".write(to: logURL, atomically: true, encoding: .utf8)
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                if let logHandle = try? FileHandle(forWritingTo: logURL) {
                    logHandle.seekToEndOfFile()
                    logHandle.write(data)
                    logHandle.closeFile()
                }
                print("[BACKEND] \(str)")
            }
        }
        
        do {
            try p.run()
            process = p
            print("✅ Backend Launched (PID: \(p.processIdentifier))")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.lock.lock()
                self.isLaunching = false
                self.lock.unlock()
            }
        } catch {
            print("❌ Failed to launch backend: \(error)")
            isLaunching = false
        }
    }
    
    func log(message: String) {
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backend.log")
        let entry = "\(Date()): \(message)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
    
    func stop() {
        lock.lock()
        defer { lock.unlock() }
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
            
            if statusCode == 200 {
                lock.lock()
                isLaunching = false
                lock.unlock()
                return true
            }
            return false
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
            request.timeoutInterval = 120
            
            let payload: [String: Any] = [
                "text": text,
                "voice": voice,
                "speed": speed,
                "volume": volume
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let task = session.dataTask(with: request)
                let id = task.taskIdentifier
                
                lock.lock()
                continuations[id] = continuation
                lock.unlock()
                
                task.resume()
                
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                    self.lock.lock()
                    self.continuations.removeValue(forKey: id)
                    self.lock.unlock()
                }
            } catch {
                continuation.finish()
            }
        }
    }
}

extension BackendService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        lock.lock()
        let continuation = continuations[id]
        lock.unlock()
        
        continuation?.yield(data)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()
        
        continuation?.finish()
    }
}
