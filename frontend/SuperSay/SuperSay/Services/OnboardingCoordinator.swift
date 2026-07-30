import Combine
import Foundation
import SwiftUI

/// Single source of truth for first-launch onboarding state.
///
/// Before v1.1 the `hasOnboarded` flag was checked ad hoc in `SuperSayApp.init`
/// and surrounding views. This coordinator centralizes the read/write/reset
/// surface and is the only thing views should consult.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    /// Persisted across launches. Default `false` — onboarding shows once.
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false

    /// Published so views can react to changes (e.g. dismiss the sheet
    /// when `markCompleted()` is called from inside it).
    @Published private(set) var version: Int = 0

    /// `true` until the user finishes (or skips) onboarding once.
    var needsOnboarding: Bool {
        !hasOnboarded
    }

    /// Mark onboarding complete. Skipping counts as complete — the user
    /// can always re-open it from Preferences (S1-C5).
    func markCompleted() {
        hasOnboarded = true
        version &+= 1
    }

    /// Reset for debug/testing. Not surfaced in production UI.
    func reset() {
        hasOnboarded = false
        version &+= 1
    }
}
