import Foundation

/// Onboarding copy lives in code constants so the wording can be edited
/// without view churn. The privacy + sign-in nudge wording is the single
/// most important sentence in v1.1 — it goes on the dashboard footer and
/// in any public post. Keep it true.
enum OnboardingCopy {
    // MARK: - Step 1 — Welcome

    static let welcomeTitle = "Welcome to SuperSay"
    static let welcomeBody = """
    SuperSay reads any selected text aloud — fast, on-device, with neural \
    voices. No cloud, no upload, no waiting on a server. Press a global \
    hotkey and the next sentence starts before the first one finishes \
    rendering.
    """

    // MARK: - Step 2 — The hotkey

    static let hotkeyTitle = "Cmd ⇧ . anywhere"
    static let hotkeyBody = """
    Select text in any app — a PDF, a webpage, your editor — then press \
    Cmd ⇧ . (period). SuperSay speaks the selection. Press it again to \
    interrupt and read something new. The shortcut is rebindable in \
    Preferences.
    """

    // MARK: - Step 3 — Voices and speed

    static let voicesTitle = "Eight voices, your speed"
    static let voicesBody = """
    Pick from eight Kokoro neural voices in the dashboard. Adjust speed \
    between 0.5× and 2×. Adjust volume independently of system audio so \
    you don't have to fight Spotify. All settings are remembered.
    """

    // MARK: - Step 4 — Audiobooks + Gemini

    static let audiobookTitle = "Audiobooks (optional, with your own key)"
    static let audiobookBody = """
    Drop a PDF onto SuperSay and it becomes an audiobook — pages cleaned, \
    references stripped, chapter breaks honored. The cleaning step uses \
    Google's Gemini Flash API, which is why it asks for your own API key \
    in Preferences. The key stays in your Keychain. The TTS itself never \
    touches Gemini — only the optional text-cleaning pass does.
    """

    // MARK: - Step 5 — Privacy + sign-in nudge

    /// The promise. Quote-verbatim in any HN/Reddit/LinkedIn post.
    static let privacyTitle = "Privacy and sign-in"
    static let privacyNudge = """
    SuperSay runs fully on your Mac. Your text never leaves this machine.

    Signing in only helps us count how many people use SuperSay and how \
    much audio gets generated — it's the only way we can show real growth \
    numbers when we share the project publicly. We never read what you \
    type. We don't store your text. We don't see your files. Counts only.

    Signing in is optional. Skipping is fine — the app works the same \
    either way.
    """

    static let privacyAuditLine = "Read PRIVACY.md — every byte we send, with file:line audit trail."

    // MARK: - Buttons

    static let skipButton = "Skip"
    static let nextButton = "Next"
    static let backButton = "Back"
    static let signInButton = "Sign in (helps us count)"
    static let maybeLaterButton = "Maybe later"
    static let getStartedButton = "Get started"
}
