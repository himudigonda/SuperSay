import Combine
import Foundation
import SwiftUI

/// Surface for SwiftUI views to observe auth state and trigger flows.
/// Persists the session JWT in Keychain via `KeychainService.sessionToken`.
@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var currentUser: AuthService.SessionResult?
    @Published private(set) var isWorking = false
    @Published var lastError: String?

    @AppStorage("anonymousUserID") private var anonID = ""

    private let service = AuthService.shared

    var isSignedIn: Bool { currentUser != nil }

    init() {
        // Restore session from Keychain if present. The token may be stale —
        // we keep using it until the server returns 401, at which point the
        // caller clears the session.
        if let token = KeychainService.get(.sessionToken) {
            // We don't have the email/userID stored locally; the only thing we
            // need at this layer is "are we signed in?" Real user details come
            // back the next time MetricsService flushes against a 2xx response.
            // For UI purposes show a placeholder; PreferencesView can refresh
            // by calling /api/supersay/auth/whoami in a future iteration.
            currentUser = AuthService.SessionResult(
                accessToken: token,
                refreshToken: KeychainService.get(.refreshToken) ?? "",
                expiresIn: 0,
                email: UserDefaults.standard.string(forKey: "lastSignedEmail"),
                displayName: UserDefaults.standard.string(forKey: "lastSignedName"),
                userID: UserDefaults.standard.string(forKey: "lastSignedUserID") ?? "unknown"
            )
        }
        // Wire the metrics service to pull the bearer dynamically. Reads
        // straight from the Keychain so the closure stays Sendable.
        MetricsService.shared.sessionTokenProvider = {
            KeychainService.get(.sessionToken)
        }
    }

    // MARK: - Public

    func signInWithGoogle() async {
        await run { [weak self] in
            guard let self else { return }
            let result = try await self.service.signInWithGoogle()
            self.persist(result)
            try? await self.service.linkAnon(bearer: result.accessToken, anonID: self.anonID)
        }
    }

    func signInWithEmail(email: String, password: String) async {
        await run { [weak self] in
            guard let self else { return }
            let result = try await self.service.emailLogin(email: email, password: password)
            self.persist(result)
            try? await self.service.linkAnon(bearer: result.accessToken, anonID: self.anonID)
        }
    }

    func signUpWithEmail(email: String, password: String) async {
        await run { [weak self] in
            guard let self else { return }
            let result = try await self.service.emailSignup(email: email, password: password)
            self.persist(result)
            try? await self.service.linkAnon(bearer: result.accessToken, anonID: self.anonID)
        }
    }

    func requestPasswordReset(email: String) async {
        await run { [weak self] in
            try await self?.service.requestPasswordReset(email: email)
        }
    }

    func signOut() {
        KeychainService.delete(.sessionToken)
        KeychainService.delete(.refreshToken)
        UserDefaults.standard.removeObject(forKey: "lastSignedEmail")
        UserDefaults.standard.removeObject(forKey: "lastSignedName")
        UserDefaults.standard.removeObject(forKey: "lastSignedUserID")
        currentUser = nil
    }

    // MARK: - Internals

    private func persist(_ s: AuthService.SessionResult) {
        KeychainService.set(s.accessToken, for: .sessionToken)
        KeychainService.set(s.refreshToken, for: .refreshToken)
        if let e = s.email { UserDefaults.standard.set(e, forKey: "lastSignedEmail") }
        if let n = s.displayName { UserDefaults.standard.set(n, forKey: "lastSignedName") }
        UserDefaults.standard.set(s.userID, forKey: "lastSignedUserID")
        currentUser = s
    }

    private func run(_ block: @escaping () async throws -> Void) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await block()
        } catch {
            lastError = (error as? AuthService.AuthError)?.errorDescription ?? error.localizedDescription
        }
    }
}
