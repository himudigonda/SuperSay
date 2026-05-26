@testable import SuperSay
import CryptoKit
import XCTest

/// Integration tests for AuthService — covers the HTTP-bound surface
/// (`emailLogin`, `emailSignup`, `requestPasswordReset`, `linkAnon`) via a
/// `URLProtocol` stub. No real network access.
///
/// What's not covered here:
///   - Google loopback flow — that requires `NSWorkspace.open` and a real
///     browser. It's covered by manual e2e and the live release-build check.
///   - Keychain round-trip — covered by SuperSayTests/KeychainService logic
///     since Keychain access from XCTest is sandboxed differently from app.
@MainActor
final class AuthServiceIntegrationTests: XCTestCase {

    private var session: URLSession!

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.handlers = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() async throws {
        StubURLProtocol.handlers = []
        try await super.tearDown()
    }

    // MARK: - PKCE invariants (RFC 7636 §4.1)

    func test_pkce_verifier_length_in_rfc_range() {
        for _ in 0..<32 {
            let v = AuthService.makePKCEVerifier()
            XCTAssertGreaterThanOrEqual(v.count, 43)
            XCTAssertLessThanOrEqual(v.count, 128)
        }
    }

    func test_pkce_verifier_characters_are_base64url() {
        // base64url alphabet: [A-Za-z0-9_-]
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        )
        for _ in 0..<16 {
            let v = AuthService.makePKCEVerifier()
            XCTAssertNil(
                v.unicodeScalars.first(where: { !allowed.contains($0) }),
                "verifier must be RFC 7636 base64url alphabet, got: \(v)"
            )
        }
    }

    func test_pkce_challenge_matches_sha256_base64url_of_verifier() {
        let v = "knownVerifier123"
        let digest = SHA256.hash(data: Data(v.utf8))
        let expected = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(AuthService.makePKCEChallenge(from: v), expected)
    }

    func test_pkce_state_token_is_unique() {
        var seen: Set<String> = []
        for _ in 0..<64 {
            let t = AuthService.randomToken()
            XCTAssertFalse(seen.contains(t), "state tokens must not collide")
            seen.insert(t)
        }
    }

    // MARK: - emailLogin happy path

    func test_emailLogin_happyPath_parsesSession() async throws {
        let svc = makeService()
        StubURLProtocol.handlers.append { req in
            XCTAssertTrue(req.url!.path.hasSuffix("/email/login"))
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return Self.jsonResponse(status: 200, body: [
                "access_token": "ATK",
                "refresh_token": "RTK",
                "expires_in": 3600,
                "user": [
                    "id":           "user-uuid",
                    "email":        "him@example.com",
                    "display_name": "Him",
                ],
            ])
        }
        let s = try await svc.emailLogin(email: "him@example.com", password: "pw")
        XCTAssertEqual(s.accessToken, "ATK")
        XCTAssertEqual(s.refreshToken, "RTK")
        XCTAssertEqual(s.expiresIn, 3600)
        XCTAssertEqual(s.email, "him@example.com")
        XCTAssertEqual(s.displayName, "Him")
        XCTAssertEqual(s.userID, "user-uuid")
    }

    // MARK: - emailLogin error mapping

    func test_emailLogin_400_propagatesServerErrorMessage() async {
        let svc = makeService()
        StubURLProtocol.handlers.append { _ in
            Self.jsonResponse(status: 400, body: [
                "error": ["code": "invalid_credentials", "message": "Invalid login"],
            ])
        }
        do {
            _ = try await svc.emailLogin(email: "x", password: "y")
            XCTFail("expected throw")
        } catch let AuthService.AuthError.serverError(msg) {
            XCTAssertEqual(msg, "Invalid login")
        } catch {
            XCTFail("expected serverError, got \(error)")
        }
    }

    func test_emailLogin_429_surfacesAsServerError() async {
        let svc = makeService()
        StubURLProtocol.handlers.append { _ in
            Self.jsonResponse(status: 429, body: [:])
        }
        do {
            _ = try await svc.emailLogin(email: "x", password: "y")
            XCTFail("expected throw")
        } catch AuthService.AuthError.serverError {
            // ok
        } catch {
            XCTFail("expected serverError, got \(error)")
        }
    }

    func test_emailLogin_malformedResponse_throwsInvalidResponse() async {
        let svc = makeService()
        StubURLProtocol.handlers.append { _ in
            Self.jsonResponse(status: 200, body: ["unexpected": "shape"])
        }
        do {
            _ = try await svc.emailLogin(email: "x", password: "y")
            XCTFail("expected throw")
        } catch AuthService.AuthError.invalidResponse {
            // ok
        } catch {
            XCTFail("expected invalidResponse, got \(error)")
        }
    }

    // MARK: - emailSignup

    func test_emailSignup_postsToCorrectPath() async throws {
        let svc = makeService()
        let pathObserved = LockBox<String>()
        StubURLProtocol.handlers.append { req in
            pathObserved.set(req.url!.path)
            return Self.jsonResponse(status: 200, body: Self.sessionBody())
        }
        _ = try await svc.emailSignup(email: "him@x.io", password: "longpasswordpw")
        XCTAssertTrue(pathObserved.get().hasSuffix("/email/signup"))
    }

    // MARK: - requestPasswordReset

    func test_requestPasswordReset_swallowsEmptyResponse() async throws {
        let svc = makeService()
        StubURLProtocol.handlers.append { _ in
            Self.jsonResponse(status: 200, body: [:])
        }
        try await svc.requestPasswordReset(email: "him@x.io")
    }

    // MARK: - linkAnon attaches Authorization

    func test_linkAnon_attachesBearerHeader_andSendsAnonID() async throws {
        let svc = makeService()
        let captured = LockBox<(auth: String?, body: [String: Any]?)>()
        StubURLProtocol.handlers.append { req in
            let body = (req.httpBodyStream?.readAll() ?? req.httpBody ?? Data())
            let parsed = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            captured.set((req.value(forHTTPHeaderField: "Authorization"), parsed))
            return Self.jsonResponse(status: 200, body: [:])
        }
        try await svc.linkAnon(bearer: "JWT_OPAQUE", anonID: "anon-abc-123")
        let (auth, body) = captured.get()
        XCTAssertEqual(auth, "Bearer JWT_OPAQUE")
        XCTAssertEqual(body?["anon_id"] as? String, "anon-abc-123")
    }

    // MARK: - signInWithGoogle preconditions

    func test_signInWithGoogle_throwsWhenClientIDNotConfigured() async {
        let svc = makeService()
        svc.googleClientID = ""
        do {
            _ = try await svc.signInWithGoogle()
            XCTFail("expected throw")
        } catch AuthService.AuthError.notConfigured {
            // ok
        } catch {
            XCTFail("expected notConfigured, got \(error)")
        }
    }

    // MARK: - Helpers

    private func makeService() -> AuthService {
        let svc = AuthService.shared
        // Point AuthService at a host that our URLProtocol stub will catch.
        // The stub matches everything regardless of host, so the value only
        // has to be a well-formed URL.
        svc.apiBase = URL(string: "https://stub.invalid/api/supersay/auth")!
        svc.googleClientID = "stub-client-id"
        // Replace URLSession.shared usage indirectly: AuthService uses
        // URLSession.shared internally, so we register StubURLProtocol with
        // URLProtocol's global registry below.
        URLProtocol.registerClass(StubURLProtocol.self)
        return svc
    }

    private static func sessionBody() -> [String: Any] {
        return [
            "access_token": "A",
            "refresh_token": "R",
            "expires_in": 3600,
            "user": ["id": "uid"],
        ]
    }

    private static func jsonResponse(status: Int, body: [String: Any]) -> (HTTPURLResponse, Data) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let resp = HTTPURLResponse(
            url: URL(string: "https://stub.invalid/")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (resp, data)
    }
}

// MARK: - Stub URLProtocol

/// Single-shot URL protocol that returns a queued response for each request.
/// Registered on `URLProtocol` globally and matched by `URLSession.shared`.
final class StubURLProtocol: URLProtocol {
    /// Each handler returns (HTTPURLResponse, body data). Pop in FIFO order.
    nonisolated(unsafe) static var handlers: [(URLRequest) -> (HTTPURLResponse, Data)] = []
    nonisolated(unsafe) static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lock.lock()
        let handler = StubURLProtocol.handlers.isEmpty ? nil : StubURLProtocol.handlers.removeFirst()
        StubURLProtocol.lock.unlock()

        guard let h = handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (resp, data) = h(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tiny LockBox to capture from a closure synchronously

final class LockBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ v: T) { lock.lock(); value = v; lock.unlock() }
    func get() -> T {
        lock.lock(); defer { lock.unlock() }
        return value!
    }
}

private extension InputStream {
    func readAll() -> Data {
        var data = Data()
        open()
        defer { close() }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while hasBytesAvailable {
            let n = read(buf, maxLength: 4096)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
