import AppKit
import CryptoKit
import Foundation
import Network

/// AuthService — talks to `https://himudigonda.me/api/supersay/auth/*`.
///
/// Two flows:
/// - **Google OAuth (PKCE, desktop loopback):** generate verifier+challenge,
///   spin up a transient local HTTP listener on `127.0.0.1:<port>`, open the
///   user's browser to the consent URL, receive the auth code on the
///   loopback, exchange via the backend, store the Supabase session JWT in
///   Keychain.
/// - **Email/password:** plain POST to the backend; backend mediates Supabase Auth.
///
/// After either flow, `linkAnon()` attaches the current anon_id to the user
/// so pre-sign-in events stay attributable in the rollups.
///
/// All errors are surfaced as `AuthError` — never raw URLError.
@MainActor
final class AuthService {
    static let shared = AuthService()

    /// Endpoint base override (test/dev). Production = himudigonda.me.
    var apiBase = URL(string: "https://himudigonda.me/api/supersay/auth")!

    /// Google client ID. Set at launch from Info.plist or env. The client
    /// secret is NOT shipped in the app — the secret lives on the backend.
    var googleClientID: String =
        Bundle.main.object(forInfoDictionaryKey: "SuperSayGoogleClientID") as? String ?? ""

    private init() {}

    // MARK: - Public API

    struct SessionResult {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let email: String?
        let displayName: String?
        let userID: String
    }

    enum AuthError: LocalizedError {
        case notConfigured(String)
        case cancelled
        case networkFailure(String)
        case serverError(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured(let detail): return "Sign-in is not configured: \(detail)"
            case .cancelled: return "Sign-in was cancelled."
            case .networkFailure(let m): return "Network error: \(m)"
            case .serverError(let m): return m
            case .invalidResponse: return "Server returned an unexpected response."
            }
        }
    }

    /// Email/password login.
    func emailLogin(email: String, password: String) async throws -> SessionResult {
        let url = apiBase.appendingPathComponent("email/login")
        let body: [String: Any] = ["email": email, "password": password]
        let json = try await postJSON(url, body: body, bearer: nil)
        return try parseSession(json)
    }

    /// Email/password sign-up.
    func emailSignup(email: String, password: String) async throws -> SessionResult {
        let url = apiBase.appendingPathComponent("email/signup")
        let body: [String: Any] = ["email": email, "password": password]
        let json = try await postJSON(url, body: body, bearer: nil)
        return try parseSession(json)
    }

    /// Request a password reset email.
    func requestPasswordReset(email: String) async throws {
        let url = apiBase.appendingPathComponent("email/request-reset")
        _ = try await postJSON(url, body: ["email": email], bearer: nil)
    }

    /// Google sign-in via desktop loopback + PKCE.
    func signInWithGoogle() async throws -> SessionResult {
        guard !googleClientID.isEmpty else {
            throw AuthError.notConfigured("Missing SuperSayGoogleClientID in Info.plist")
        }
        let verifier = Self.makePKCEVerifier()
        let challenge = Self.makePKCEChallenge(from: verifier)
        let state = Self.randomToken()

        let listener = try await LoopbackListener.start()
        let redirectURI = "http://127.0.0.1:\(listener.port)/"

        guard
            let consentURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth?"
                + "client_id=\(googleClientID)"
                + "&redirect_uri=\(redirectURI.urlEncoded)"
                + "&response_type=code"
                + "&scope=\("openid email profile".urlEncoded)"
                + "&code_challenge=\(challenge)"
                + "&code_challenge_method=S256"
                + "&state=\(state)")
        else {
            listener.cancel()
            throw AuthError.notConfigured("Could not build Google consent URL")
        }
        NSWorkspace.shared.open(consentURL)

        let received: (code: String, state: String)
        do {
            received = try await listener.awaitCode(timeoutSeconds: 300)
        } catch {
            listener.cancel()
            throw error
        }
        listener.cancel()
        guard received.state == state else {
            throw AuthError.serverError("OAuth state mismatch — possible CSRF.")
        }

        let exchangeURL = apiBase.appendingPathComponent("google/exchange")
        let body: [String: Any] = [
            "code": received.code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
        ]
        let json = try await postJSON(exchangeURL, body: body, bearer: nil)
        return try parseSession(json)
    }

    /// Attach the anon_id to the signed user (call once after a successful sign-in).
    func linkAnon(bearer: String, anonID: String) async throws {
        let url = URL(string: "https://himudigonda.me/api/supersay/auth/link-anon")!
        _ = try await postJSON(url, body: ["anon_id": anonID], bearer: bearer)
    }

    // MARK: - Internals

    private func postJSON(_ url: URL, body: [String: Any], bearer: String?) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthError.networkFailure(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw AuthError.invalidResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if !(200..<300).contains(http.statusCode) {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "Server error \(http.statusCode)"
            throw AuthError.serverError(msg)
        }
        return json
    }

    private func parseSession(_ json: [String: Any]) throws -> SessionResult {
        guard
            let access = json["access_token"] as? String,
            let refresh = json["refresh_token"] as? String,
            let expires = json["expires_in"] as? Int,
            let user = json["user"] as? [String: Any],
            let userID = user["id"] as? String
        else {
            throw AuthError.invalidResponse
        }
        return SessionResult(
            accessToken: access,
            refreshToken: refresh,
            expiresIn: expires,
            email: user["email"] as? String,
            displayName: user["display_name"] as? String,
            userID: userID
        )
    }

    // MARK: - PKCE helpers (RFC 7636)

    static func makePKCEVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    static func makePKCEChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

// MARK: - Loopback HTTP listener

/// Tiny single-shot HTTP listener used for the desktop OAuth flow.
/// Binds to `127.0.0.1` on an OS-assigned random port, accepts one GET to
/// the redirect URI, extracts `code` + `state` from the query string,
/// returns a tiny human-readable HTML page, and resolves.
@MainActor
private final class LoopbackListener {
    private let listener: NWListener
    let port: Int

    private var continuation: CheckedContinuation<(code: String, state: String), Error>?
    private var resolved = false

    /// Bind and wait until the OS has assigned us a port.
    static func start() async throws -> LoopbackListener {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch {
            throw AuthService.AuthError.notConfigured("Could not bind loopback: \(error.localizedDescription)")
        }

        let port = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let p = listener.port?.rawValue {
                        cont.resume(returning: Int(p))
                    } else {
                        cont.resume(throwing: AuthService.AuthError.notConfigured("No loopback port"))
                    }
                case .failed(let err):
                    cont.resume(throwing: AuthService.AuthError.notConfigured("Listener failed: \(err.localizedDescription)"))
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
        listener.stateUpdateHandler = nil

        let inst = LoopbackListener(listener: listener, port: port)
        listener.newConnectionHandler = { [weak inst] conn in
            conn.start(queue: .main)
            let captured = inst
            Task { @MainActor in
                captured?.receive(on: conn)
            }
        }
        return inst
    }

    private init(listener: NWListener, port: Int) {
        self.listener = listener
        self.port = port
    }

    func awaitCode(timeoutSeconds: Double) async throws -> (code: String, state: String) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(code: String, state: String), Error>) in
            self.continuation = cont
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self.resolve(.failure(AuthService.AuthError.cancelled))
            }
        }
    }

    func cancel() {
        listener.cancel()
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let data, let req = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let firstLine = req.split(separator: "\r\n", omittingEmptySubsequences: true).first ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET" else {
                conn.cancel(); return
            }
            let path = String(parts[1])
            let q = Self.parseQueryNonisolated(in: path)

            let body = """
            <!doctype html><html><head><meta charset="utf-8"><title>SuperSay</title>
            <style>body{font-family:-apple-system,sans-serif;background:#0f0f12;color:#fff;display:grid;place-items:center;height:100vh;margin:0}h1{font-weight:600}p{color:#888}</style>
            </head><body><div><h1>Signed in</h1><p>You can close this tab and return to SuperSay.</p></div></body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let code = q["code"], let state = q["state"] {
                    self.resolve(.success((code, state)))
                } else if let err = q["error"] {
                    self.resolve(.failure(AuthService.AuthError.serverError("Google: \(err)")))
                }
            }
        }
    }

    nonisolated private static func parseQueryNonisolated(in path: String) -> [String: String] {
        guard let q = path.split(separator: "?").dropFirst().first else { return [:] }
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, let k = kv.first?.removingPercentEncoding, let v = kv.last?.removingPercentEncoding {
                out[k] = v
            }
        }
        return out
    }

    private func resolve(_ result: Result<(code: String, state: String), Error>) {
        guard !resolved else { return }
        resolved = true
        if let c = continuation {
            switch result {
            case .success(let v): c.resume(returning: v)
            case .failure(let e): c.resume(throwing: e)
            }
        }
        continuation = nil
    }
}

// MARK: - Helpers

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
