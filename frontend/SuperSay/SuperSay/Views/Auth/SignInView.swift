import SwiftUI

/// Single sheet that handles sign-in (Google or email/password) and sign-up.
/// Shown from the onboarding nudge step and from Preferences → Account.
struct SignInView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Sign up"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var didTriggerReset = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.cyan.gradient)
                Text(mode.rawValue)
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            // Mode picker
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("We never see your text. Counts only — see PRIVACY.md.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Google
            Button {
                Task { await auth.signInWithGoogle() }
            } label: {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Continue with Google")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(auth.isWorking)

            Divider().overlay(Text("or").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 6))

            // Email + password
            VStack(spacing: 8) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                SecureField(mode == .signUp ? "Password (≥10 chars)" : "Password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
            }

            if let err = auth.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    switch mode {
                    case .signIn: await auth.signInWithEmail(email: email, password: password)
                    case .signUp: await auth.signUpWithEmail(email: email, password: password)
                    }
                    if auth.isSignedIn { dismiss() }
                }
            } label: {
                Text(mode == .signUp ? "Create account" : "Sign in")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(auth.isWorking || email.isEmpty || password.isEmpty)

            if mode == .signIn {
                Button(didTriggerReset ? "Reset email sent — check inbox" : "Forgot password?") {
                    Task {
                        await auth.requestPasswordReset(email: email)
                        didTriggerReset = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .disabled(auth.isWorking || email.isEmpty || didTriggerReset)
            }

            if auth.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(28)
        .frame(width: 380)
        .onChange(of: auth.isSignedIn) { _, signed in
            if signed { dismiss() }
        }
    }
}
