import SwiftUI

/// Five-step onboarding shown once on first launch.
///
/// - Step 1: Welcome
/// - Step 2: The Cmd ⇧ . hotkey
/// - Step 3: Voices + speed
/// - Step 4: Audiobooks + Gemini explanation
/// - Step 5: Privacy + transparent sign-in nudge
///
/// The sign-in button is wired via `onSignInTapped` so this view doesn't
/// need to know about `AuthViewModel`. While auth isn't shipped yet, the
/// closure is a no-op that just dismisses; once `SignInView` lands the
/// host wires it up there.
struct OnboardingView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator

    /// Called when the user taps the "Sign in" CTA on step 5. The host
    /// presents the sign-in sheet; on completion the host calls
    /// `coordinator.markCompleted()`.
    var onSignInTapped: () -> Void = {}

    @State private var step: Int = 0
    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            // Header — skip is always available, even on the last step.
            HStack {
                Spacer()
                Button(OnboardingCopy.skipButton) {
                    coordinator.markCompleted()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
                .padding(.trailing, 24)
            }

            // Page indicator (small, unobtrusive)
            HStack(spacing: 8) {
                ForEach(0 ..< stepCount, id: \.self) { idx in
                    Capsule()
                        .fill(idx == step ? Color.cyan : Color.secondary.opacity(0.25))
                        .frame(width: idx == step ? 24 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: step)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 24)

            // Step content
            ZStack {
                switch step {
                case 0: stepWelcome
                case 1: stepHotkey
                case 2: stepVoices
                case 3: stepAudiobook
                default: stepPrivacy
                }
            }
            .frame(maxWidth: 520)
            .transition(.opacity)

            Spacer(minLength: 24)

            // Footer — Back / Next or sign-in CTA on the last step.
            HStack {
                if step > 0 {
                    Button(OnboardingCopy.backButton) {
                        withAnimation { step -= 1 }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Spacer().frame(width: 60)
                }

                Spacer()

                if step < stepCount - 1 {
                    Button(OnboardingCopy.nextButton) {
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .keyboardShortcut(.defaultAction)
                } else {
                    // Final step: sign-in vs. maybe-later, equal weight.
                    HStack(spacing: 10) {
                        Button(OnboardingCopy.maybeLaterButton) {
                            coordinator.markCompleted()
                        }
                        .buttonStyle(.bordered)

                        Button(OnboardingCopy.signInButton) {
                            onSignInTapped()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(.thinMaterial)
    }

    // MARK: - Step views

    private var stepWelcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(.cyan.gradient)
            Text(OnboardingCopy.welcomeTitle)
                .font(.system(size: 28, weight: .bold))
            Text(OnboardingCopy.welcomeBody)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }

    private var stepHotkey: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                kbd("⌘"); kbd("⇧"); kbd(".")
            }
            Text(OnboardingCopy.hotkeyTitle)
                .font(.system(size: 24, weight: .bold))
            Text(OnboardingCopy.hotkeyBody)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }

    private var stepVoices: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(.cyan.gradient)
            Text(OnboardingCopy.voicesTitle)
                .font(.system(size: 24, weight: .bold))
            Text(OnboardingCopy.voicesBody)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }

    private var stepAudiobook: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 52))
                .foregroundStyle(.cyan.gradient)
            Text(OnboardingCopy.audiobookTitle)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(OnboardingCopy.audiobookBody)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
    }

    private var stepPrivacy: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.cyan.gradient)
            Text(OnboardingCopy.privacyTitle)
                .font(.system(size: 24, weight: .bold))
            Text(OnboardingCopy.privacyNudge)
                .font(.system(size: 13))
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

            // Audit link
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(OnboardingCopy.privacyAuditLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func kbd(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
            )
    }
}
