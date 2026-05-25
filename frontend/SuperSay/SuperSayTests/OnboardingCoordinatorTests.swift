@testable import SuperSay
import XCTest

/// Tests for OnboardingCoordinator (S1-E3 / G6).
@MainActor
final class OnboardingCoordinatorTests: XCTestCase {

    override func setUp() async throws {
        // Each test starts with a clean flag.
        UserDefaults.standard.removeObject(forKey: "hasOnboarded")
    }

    func test_freshInstall_needsOnboarding() {
        let coord = OnboardingCoordinator()
        XCTAssertTrue(coord.needsOnboarding)
    }

    func test_afterMarkCompleted_doesNotNeedOnboarding() {
        let coord = OnboardingCoordinator()
        coord.markCompleted()
        XCTAssertFalse(coord.needsOnboarding)
    }

    func test_resetRestoresOnboarding() {
        let coord = OnboardingCoordinator()
        coord.markCompleted()
        XCTAssertFalse(coord.needsOnboarding)
        coord.reset()
        XCTAssertTrue(coord.needsOnboarding)
    }

    func test_versionBumpsOnStateChange() {
        let coord = OnboardingCoordinator()
        let v0 = coord.version
        coord.markCompleted()
        XCTAssertNotEqual(v0, coord.version, "version should bump so SwiftUI can react")
    }
}
