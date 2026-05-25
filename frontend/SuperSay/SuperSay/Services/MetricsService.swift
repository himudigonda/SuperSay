import Foundation
import SwiftUI

/// MetricsService v2 — counts-only analytics with a whitelisted outbox.
///
/// Design contract (see `docs/specs/accounts-analytics.md`):
/// - Sends ONLY the keys in `Props.allowedKeys`. Any unknown key is dropped
///   on the client *before* HTTP serialization. The server re-enforces this.
/// - Events are batched (flush every 30s OR when 20 events queue up).
/// - When the user has signed in, requests carry `Authorization: Bearer <jwt>`.
/// - The anonymous ID is always included so pre-sign-in events still attribute
///   correctly once `link-anon` is called.
/// - Honors the existing `telemetryEnabled` toggle as a hard kill switch:
///   when off, the outbox is not even written to — nothing leaves the box.
/// - Outbox is persisted to UserDefaults across app restarts (cap 200).
/// - Endpoint: POST /api/supersay/events on himudigonda.me.
final class MetricsService {
    static let shared = MetricsService()

    @AppStorage("anonymousUserID") private var userID = UUID().uuidString
    @AppStorage("telemetryEnabled") private var enabled = true

    private let endpoint = URL(string: "https://himudigonda.me/api/supersay/events")!
    private let outboxKey = "metrics_outbox_v2"
    private let outboxCap = 200
    private let flushBatchSize = 20
    private let flushIntervalSeconds: TimeInterval = 30

    /// Optional bearer-token supplier. Wired up by `AuthService` once it lands.
    /// Returning nil means "send as anon."
    var sessionTokenProvider: () -> String? = { nil }

    private let queue = DispatchQueue(label: "com.himudigonda.SuperSay.metrics", qos: .utility)
    private var outbox: [Event] = []
    private var flushTimer: Timer?

    private init() {
        if userID.isEmpty { userID = UUID().uuidString }
        outbox = loadOutbox()
        scheduleFlushTimer()
    }

    // MARK: - Public surface (call-site compatible with v1)

    func trackLaunch() {
        enqueue(event: "app_launch", props: [:])
    }

    /// Emit a `generation` event at playback completion with the rendered length.
    /// `chars` is the count only — never the text.
    func trackGeneration(chars: Int, voice: String, speed: Double, audioSeconds: Double) {
        enqueue(event: "generation", props: [
            "chars": chars,
            "voice": voice,
            "speed": speed,
            "audio_seconds": audioSeconds,
        ])
    }

    func trackExport(audioSeconds: Double) {
        enqueue(event: "export", props: ["audio_seconds": audioSeconds])
    }

    func trackAudiobookUpload(pages: Int, fileKind: String) {
        enqueue(event: "audiobook_upload", props: ["pages": pages, "file_kind": fileKind])
    }

    func trackAudiobookPlay(bookIDHash: String, secondsPlayed: Double) {
        enqueue(event: "audiobook_play", props: [
            "book_id_hash": bookIDHash,
            "seconds_played": secondsPlayed,
        ])
    }

    func trackGeminiClean(pages: Int, charsOut: Int) {
        enqueue(event: "gemini_clean", props: ["pages": pages, "chars_out": charsOut])
    }

    // MARK: - Core

    private func enqueue(event: String, props rawProps: [String: Any]) {
        guard enabled else { return }
        guard Event.allowedNames.contains(event) else {
            #if DEBUG
            print("⚠️ Metrics: unknown event '\(event)' dropped")
            #endif
            return
        }
        let cleanedProps = Props.whitelist(rawProps)
        let evt = Event(
            name: event,
            props: cleanedProps,
            timestamp: Date()
        )
        queue.async { [weak self] in
            guard let self else { return }
            outbox.append(evt)
            if outbox.count > outboxCap {
                outbox.removeFirst(outbox.count - outboxCap)
            }
            persistOutbox()
            if outbox.count >= flushBatchSize {
                flushLocked()
            }
        }
    }

    /// Force-flush the outbox. Safe to call from any thread.
    func flush() {
        queue.async { [weak self] in self?.flushLocked() }
    }

    private func flushLocked() {
        guard enabled else {
            outbox.removeAll()
            persistOutbox()
            return
        }
        guard !outbox.isEmpty else { return }
        let batch = outbox
        let payload: [String: Any] = [
            "anon_id": userID,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            "platform": "macOS",
            "events": batch.map { $0.serialized() },
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            #if DEBUG
            print("⚠️ Metrics: serialization failed; dropping batch")
            #endif
            outbox.removeAll()
            persistOutbox()
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionTokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        // Optimistic: clear the outbox once we hand the request to URLSession.
        // If the request fails, individual events are lost (counts only — safe).
        outbox.removeAll()
        persistOutbox()

        URLSession.shared.dataTask(with: request) { _, response, _ in
            #if DEBUG
            if let http = response as? HTTPURLResponse {
                print("📡 Metrics: flushed \(batch.count) events → \(http.statusCode)")
            }
            #endif
        }.resume()
    }

    private func scheduleFlushTimer() {
        // Timer must live on a runloop; use the main queue's runloop.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            flushTimer = Timer.scheduledTimer(
                withTimeInterval: flushIntervalSeconds,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
    }

    // MARK: - Outbox persistence

    private func persistOutbox() {
        let serialized = outbox.map { $0.serialized() }
        guard let data = try? JSONSerialization.data(withJSONObject: serialized) else { return }
        UserDefaults.standard.set(data, forKey: outboxKey)
    }

    private func loadOutbox() -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: outboxKey),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap(Event.fromSerialized)
    }
}

// MARK: - Event + Props (testable boundary)

extension MetricsService {
    struct Event {
        let name: String
        let props: [String: Any]
        let timestamp: Date

        nonisolated static let allowedNames: Set<String> = [
            "app_launch", "generation", "export",
            "audiobook_upload", "audiobook_play", "gemini_clean",
        ]

        func serialized() -> [String: Any] {
            // ISO-8601 with milliseconds so the server can sort if it wants
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return [
                "event": name,
                "ts": fmt.string(from: timestamp),
                "props": props,
            ]
        }

        nonisolated static func fromSerialized(_ raw: [String: Any]) -> Event? {
            guard let name = raw["event"] as? String,
                  allowedNames.contains(name) else { return nil }
            let props = raw["props"] as? [String: Any] ?? [:]
            let ts: Date
            if let s = raw["ts"] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                ts = fmt.date(from: s) ?? Date()
            } else {
                ts = Date()
            }
            return Event(name: name, props: Props.whitelist(props), timestamp: ts)
        }
    }

    enum Props {
        /// Closed whitelist — see `docs/specs/accounts-analytics.md` §5.2.
        /// Any key not in this map is dropped.
        nonisolated static let allowedKeys: [String: @Sendable (Any) -> Any?] = [
            "chars":          { ($0 as? Int).flatMap { $0 >= 0 ? $0 : nil } },
            "voice":          { ($0 as? String) },
            "speed":          { v in (v as? Double).flatMap { $0 >= 0.5 && $0 <= 2.0 ? $0 : nil } },
            "volume":         { v in (v as? Double).flatMap { $0 >= 0.0 && $0 <= 1.5 ? $0 : nil } },
            "audio_seconds":  { v in (v as? Double).flatMap { $0 >= 0 ? $0 : nil } },
            "pages":          { ($0 as? Int).flatMap { $0 >= 0 ? $0 : nil } },
            "file_kind":      { v in
                guard let s = v as? String, ["pdf", "txt", "epub"].contains(s) else { return nil }
                return s
            },
            "book_id_hash":   { v in
                guard let s = v as? String,
                      s.count == 64,
                      s.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
                return s
            },
            "chars_out":      { ($0 as? Int).flatMap { $0 >= 0 ? $0 : nil } },
            "seconds_played": { v in (v as? Double).flatMap { $0 >= 0 ? $0 : nil } },
        ]

        /// Strip everything not in `allowedKeys` and validate value shapes.
        /// This is *defense in depth*; the server enforces the same whitelist.
        nonisolated static func whitelist(_ raw: [String: Any]) -> [String: Any] {
            var out: [String: Any] = [:]
            for (key, validator) in allowedKeys {
                if let v = raw[key], let cleaned = validator(v) {
                    out[key] = cleaned
                }
            }
            return out
        }
    }
}
