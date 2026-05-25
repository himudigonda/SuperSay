@testable import SuperSay
import XCTest

/// Tests for AuthService (S1-C1 / G6).
///
/// Network paths require a live backend so they're covered by manual
/// e2e in the sprint verification. Here we test the pure PKCE helpers.
@MainActor
final class AuthServiceTests: XCTestCase {

    func test_pkceVerifier_isUrlSafe_andLongEnough() {
        let verifier = AuthService.makePKCEVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43, "RFC 7636 requires ≥ 43 chars")
        XCTAssertLessThanOrEqual(verifier.count, 128, "RFC 7636 requires ≤ 128 chars")
        // No padding, no +, no /
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertFalse(verifier.contains("="))
    }

    func test_pkceChallenge_isDeterministic_fromVerifier() {
        let verifier = "test-verifier-string"
        let c1 = AuthService.makePKCEChallenge(from: verifier)
        let c2 = AuthService.makePKCEChallenge(from: verifier)
        XCTAssertEqual(c1, c2, "Same verifier must produce same challenge (S256 is deterministic).")
    }

    func test_pkceVerifier_isUnique_acrossCalls() {
        let a = AuthService.makePKCEVerifier()
        let b = AuthService.makePKCEVerifier()
        XCTAssertNotEqual(a, b, "Random PKCE verifiers must not collide.")
    }

    func test_randomToken_isUnique() {
        let a = AuthService.randomToken()
        let b = AuthService.randomToken()
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThan(a.count, 10)
    }
}
