# SuperSay Frontend (macOS)

Native macOS app for SuperSay, built with **SwiftUI** + **AppKit**, targeting macOS 14.0+. Communicates exclusively with the bundled Python backend on `127.0.0.1:10101`; the only external network traffic is optional analytics + sign-in (off-by-default for sign-in, toggleable for analytics).

## 🏗️ Core components

### Services (`Services/`)

| File | Role |
| :--- | :--- |
| `LaunchManager.swift` | Extracts the bundled `SuperSayServer.zip` on first run, starts the backend process, polls `/health`. |
| `BackendService.swift` | HTTP streaming client for `/speak`; lifecycle owner for the backend process. |
| `AudioService.swift` | `AVAudioEngine` consumer — schedules PCM buffers, tracks rendered frames, computes the headline `audio_seconds` metric. |
| `AudiobookService.swift` | Audiobook REST + SSE client (upload → estimate → start → status stream → audio fetch). |
| `MetricsService.swift` | **Counts-only** batched outbox (20 events / 30s flush). Closed props whitelist enforced before HTTP serialization. Hard kill switch via `telemetryEnabled` toggle. |
| `AuthService.swift` | Optional sign-in. Google OAuth desktop loopback + PKCE (no client secret in the app). Email/password POST to `himudigonda.me`. Stores Supabase JWT in Keychain. |
| `KeychainService.swift` | Three slots: `geminiAPIKey`, `sessionToken`, `refreshToken`. |
| `OnboardingCoordinator.swift` | Single source of truth for first-launch + the `hasOnboarded` flag. |
| `HistoryManager.swift` | The Vault — local TTS history JSON store. |
| `SystemService.swift` | AppleScript-based Spotify / Music volume ducking. |

### View models (`ViewModels/`)

- `DashboardViewModel.swift` — central state: voice, speed, status, backend health, the active `Task` for any in-flight `/speak` stream.
- `AudiobookViewModel.swift` — library, upload modal, playback, processing state.
- `AuthViewModel.swift` — `@Published currentUser` / `isSignedIn`, sign-in/out methods, restores session from Keychain on launch, wires `MetricsService.sessionTokenProvider`.

### Views (`Views/`)

- `SuperSayWindow.swift` — top-level NavigationSplitView. Presents `OnboardingView` on first launch (E1) and a `SignInView` sheet when the user taps Sign in (C3).
- `MainDashboardView.swift` — TTS surface (input, voice picker, transport bar).
- `VaultView.swift` — local history.
- `PreferencesView.swift` — every settings panel, including the new **Account** section (signed-in email + Sign out, or "Sign in to count yourself" CTA when anonymous).
- `Audiobook/` — `AudiobookLibraryView`, `AudiobookPlayerView`, `UploadEstimateModal`, `NowPlayingBar`, `AudiobookCardView`, `AudiobookToastView`, `CompletionSummaryModal`.
- `Auth/SignInView.swift` — segmented sign-in / sign-up sheet with Google + email/password.
- `Onboarding/` — `OnboardingView`, `OnboardingCopy` (the privacy nudge text lives here as a constant so it's edit-once).

### Utilities (`Utilities/`)

- `Shortcuts.swift` — global hotkey registration (Cmd ⇧ ., Cmd ⇧ /, Cmd ⇧ ,, Cmd ⇧ M).
- `SelectionManager.swift` — screen text capture via the macOS Accessibility API.
- `TextProcessor.swift` — number expansion, URL cleaning, ligature fixing.

## 🔒 Privacy boundary

Two layers of defense against accidentally leaking text:

1. **Client whitelist** (`MetricsService.Props.allowedKeys`) — any key not in the closed list is dropped before HTTP serialization.
2. **Server whitelist** (`himudigonda.me/lib/supersay-validate.js`) — re-validates before insert.

Plus the **kill switch**: `@AppStorage("telemetryEnabled")` blocks `enqueue()` at the door. With telemetry off, zero requests leave the app.

Full audit trail (with `file:line` refs) lives in [`../PRIVACY.md`](../PRIVACY.md).

## 🔨 Building

1. **Prepare backend**: `Resources/SuperSayServer.zip` must exist (run `make backend` from the repo root).
2. **Configure auth (developer builds)**: paste your Google OAuth Client ID into `SuperSay/Info.plist` under `SuperSayGoogleClientID`. The client *secret* never goes in the app — it lives on the server.
3. **Open `SuperSay.xcodeproj`** in Xcode and Run, or `make app` for a Release build.

## 🧪 Tests

`xcodebuild test -project SuperSay.xcodeproj -scheme SuperSay -destination "platform=macOS"`. Or `Cmd+U` in Xcode. The test target covers:

- `TextProcessor` sanitization (URLs, handles, ligatures, abbreviations).
- `MetricsService.Props.whitelist` — guarantees `text`, unknown keys, and out-of-range values are dropped.
- `MetricsService.Event` round-trip through JSON serialization.
- `OnboardingCoordinator` state transitions.
- `AuthService` PKCE helpers (RFC 7636 length, determinism, uniqueness).
