@testable import SuperSay
import XCTest

/// State-machine tests for AuthViewModel.
///
/// What we lock down here is the observable contract for the SwiftUI
/// surface — `isSignedIn`, `currentUser`, `lastError`, and `isWorking`
/// transitions. Real HTTP calls go through `URLProtocol` (see
/// `AuthServiceIntegrationTests.StubURLProtocol`).
@MainActor
final class AuthViewModelStateMachineTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.handlers = []
        URLProtocol.registerClass(StubURLProtocol.self)
        // Always start each test from a clean Keychain + Defaults slate.
        KeychainService.delete(.sessionToken)
        KeychainService.delete(.refreshToken)
        UserDefaults.standard.removeObject(forKey: "lastSignedEmail")
        UserDefaults.standard.removeObject(forKey: "lastSignedName")
        UserDefaults.standard.removeObject(forKey: "lastSignedUserID")
        // Pin AuthService at a host the stub will catch.
        AuthService.shared.apiBase = URL(string: "https://stub.invalid/api/supersay/auth")!
        AuthService.shared.googleClientID = "stub-client-id"
    }

    override func tearDown() async throws {
        StubURLProtocol.handlers = []
        KeychainService.delete(.sessionToken)
        KeychainService.delete(.refreshToken)
        try await super.tearDown()
    }

    // MARK: - Initial state

    func test_initial_state_isAnonymous_whenNoKeychainToken() {
        let vm = AuthViewModel()
        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(vm.currentUser)
        XCTAssertNil(vm.lastError)
        XCTAssertFalse(vm.isWorking)
    }

    func test_initial_state_restoresSession_whenKeychainTokenPresent() {
        KeychainService.set("STORED_JWT", for: .sessionToken)
        KeychainService.set("STORED_RTK", for: .refreshToken)
        UserDefaults.standard.set("him@example.com", forKey: "lastSignedEmail")
        UserDefaults.standard.set("Himansh", forKey: "lastSignedName")
        UserDefaults.standard.set("user-uuid", forKey: "lastSignedUserID")

        let vm = AuthViewModel()
        XCTAssertTrue(vm.isSignedIn)
        XCTAssertEqual(vm.currentUser?.accessToken, "STORED_JWT")
        XCTAssertEqual(vm.currentUser?.refreshToken, "STORED_RTK")
        XCTAssertEqual(vm.currentUser?.email, "him@example.com")
        XCTAssertEqual(vm.currentUser?.displayName, "Himansh")
        XCTAssertEqual(vm.currentUser?.userID, "user-uuid")
    }

    // MARK: - Sign-in transitions

    func test_emailLogin_happy_movesToSignedIn() async {
        let vm = AuthViewModel()
        StubURLProtocol.handlers.append { _ in
            Self.sessionJSON()
        }
        // linkAnon call after login
        StubURLProtocol.handlers.append { _ in
            Self.emptyJSON()
        }
        await vm.signInWithEmail(email: "x@y.io", password: "longpass123")
        XCTAssertTrue(vm.isSignedIn)
        XCTAssertNil(vm.lastError)
        XCTAssertFalse(vm.isWorking)
        XCTAssertEqual(vm.currentUser?.accessToken, "ATK")
        XCTAssertEqual(KeychainService.get(.sessionToken), "ATK", "session token persisted to Keychain")
    }

    func test_emailLogin_failure_leavesUnsigned_andRecordsLastError() async {
        let vm = AuthViewModel()
        StubURLProtocol.handlers.append { _ in
            let body = try? JSONSerialization.data(withJSONObject: [
                "error": ["code": "bad", "message": "Invalid login"],
            ])
            let resp = HTTPURLResponse(
                url: URL(string: "https://stub/")!,
                statusCode: 400,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (resp, body ?? Data())
        }
        await vm.signInWithEmail(email: "x@y.io", password: "wrong")
        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNotNil(vm.lastError)
        XCTAssertTrue(vm.lastError?.contains("Invalid login") == true)
        XCTAssertNil(KeychainService.get(.sessionToken))
    }

    // MARK: - Sign-out clears state

    func test_signOut_clearsEverything() async {
        let vm = AuthViewModel()
        StubURLProtocol.handlers.append { _ in Self.sessionJSON() }
        StubURLProtocol.handlers.append { _ in Self.emptyJSON() }
        await vm.signInWithEmail(email: "x@y.io", password: "longpass")
        XCTAssertTrue(vm.isSignedIn)

        vm.signOut()
        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(vm.currentUser)
        XCTAssertNil(KeychainService.get(.sessionToken))
        XCTAssertNil(KeychainService.get(.refreshToken))
        XCTAssertNil(UserDefaults.standard.string(forKey: "lastSignedEmail"))
    }

    // MARK: - Concurrent retries clear prior error

    func test_secondAttempt_clearsPreviousError() async {
        let vm = AuthViewModel()
        // First: fail
        StubURLProtocol.handlers.append { _ in Self.errorJSON(message: "Bad 1") }
        await vm.signInWithEmail(email: "x@y.io", password: "wrong")
        XCTAssertNotNil(vm.lastError)

        // Second: succeed → lastError must be nil
        StubURLProtocol.handlers.append { _ in Self.sessionJSON() }
        StubURLProtocol.handlers.append { _ in Self.emptyJSON() }
        await vm.signInWithEmail(email: "x@y.io", password: "right")
        XCTAssertNil(vm.lastError)
        XCTAssertTrue(vm.isSignedIn)
    }

    // MARK: - Reset request fires without changing sign-in state

    func test_requestPasswordReset_doesNotChangeSignedInFlag() async {
        let vm = AuthViewModel()
        StubURLProtocol.handlers.append { _ in Self.emptyJSON() }
        await vm.requestPasswordReset(email: "x@y.io")
        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(vm.lastError)
    }

    // MARK: - Helpers

    private static func sessionJSON() -> (HTTPURLResponse, Data) {
        let body: [String: Any] = [
            "access_token": "ATK",
            "refresh_token": "RTK",
            "expires_in": 3600,
            "user": [
                "id": "uid-1",
                "email": "x@y.io",
                "display_name": "X",
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let resp = HTTPURLResponse(
            url: URL(string: "https://stub/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (resp, data)
    }

    private static func emptyJSON() -> (HTTPURLResponse, Data) {
        let data = (try? JSONSerialization.data(withJSONObject: [:])) ?? Data()
        let resp = HTTPURLResponse(
            url: URL(string: "https://stub/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (resp, data)
    }

    private static func errorJSON(message: String) -> (HTTPURLResponse, Data) {
        let body: [String: Any] = [
            "error": ["code": "x", "message": message],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let resp = HTTPURLResponse(
            url: URL(string: "https://stub/")!,
            statusCode: 400,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (resp, data)
    }
}
