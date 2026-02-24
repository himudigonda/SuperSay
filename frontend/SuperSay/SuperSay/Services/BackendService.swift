import AppKit
import Combine
import Foundation

/// A thread-safe service to manage the Python backend process and handle streaming requests.
final class BackendService: NSObject, @unchecked Sendable {
    private var process: Process?
    private let stateQueue = DispatchQueue(label: "com.supersay.backend.state", qos: .userInitiated)

    // Thread-safe state managed by stateQueue
    private var _isLaunching = false
    var isLaunching: Bool {
        stateQueue.sync { _isLaunching }
    }

    private let baseURL = URL(string: "http://127.0.0.1:10101")!
    private var continuations: [Int: AsyncStream<Data>.Continuation] = [:]

    /// Shared session for streaming this is a
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 10
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - Process Management

    func start() {
        stateQueue.sync {
            guard process == nil, !_isLaunching else { return }
            _isLaunching = true
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.himudigonda.SuperSay"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let executableURL = appSupport.appendingPathComponent("SuperSayServer/SuperSayServer")

        // Just check if LaunchManager did its job
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            stateQueue.sync { _isLaunching = false }
            print("❌ Backend binary not ready yet.")
            return
        }

        // Kill existing instances
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
            stateQueue.sync { self.process = p }
            print("✅ Backend Launched (PID: \(p.processIdentifier))")

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.stateQueue.sync { self._isLaunching = false }
            }
        } catch {
            print("❌ Backend Launch Failed: \(error)")
            stateQueue.sync { _isLaunching = false }
        }
    }

    func stop() {
        stateQueue.sync {
            process?.terminate()
            process = nil
        }

        let task = Process()
        task.launchPath = "/usr/bin/pkill"
        task.arguments = ["-9", "-f", "SuperSayServer"]
        try? task.run()
    }

    func exportLogs() {
        let fileManager = FileManager.default
        let bundleID = Bundle.main.bundleIdentifier ?? "com.himudigonda.SuperSay"
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(bundleID)
        let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]

        let logsToExport = ["backend.log", "frontend.log"]
        let timestamp = Int(Date().timeIntervalSince1970)

        for logName in logsToExport {
            let sourceURL = appSupport.appendingPathComponent(logName)
            let destinationURL = desktop.appendingPathComponent("SuperSay_\(logName)_\(timestamp).txt")

            if fileManager.fileExists(atPath: sourceURL.path) {
                try? fileManager.copyItem(at: sourceURL, to: destinationURL)
                print("✅ Exported \(logName) to Desktop")
            } else {
                print("⚠️ Could not find \(logName) at \(sourceURL.path)")
            }
        }

        // Show in Finder
        NSWorkspace.shared.activateFileViewerSelecting([desktop])
    }

    func checkHealth() async -> Bool {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let online = (response as? HTTPURLResponse)?.statusCode == 200
            if online {
                stateQueue.sync { _isLaunching = false }
            }
            return online
        } catch {
            return false
        }
    }

    func streamAudio(text: String, voice: String, speed: Double, volume: Double) -> AsyncStream<Data> {
        AsyncStream { continuation in
            let url = baseURL.appendingPathComponent("speak")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120

            let payload: [String: Any] = ["text": text, "voice": voice, "speed": speed, "volume": volume]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let task = session.dataTask(with: request)
                let id = task.taskIdentifier

                stateQueue.sync {
                    continuations[id] = continuation
                }

                task.resume()

                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                    self.stateQueue.async {
                        self.continuations.removeValue(forKey: id)
                    }
                }
            } catch {
                continuation.finish()
            }
        }
    }
}

extension BackendService: URLSessionDataDelegate {
    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        stateQueue.sync {
            continuations[id]?.yield(data)
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError _: Error?) {
        let id = task.taskIdentifier
        stateQueue.sync {
            continuations[id]?.finish()
            continuations.removeValue(forKey: id)
        }
    }
}
