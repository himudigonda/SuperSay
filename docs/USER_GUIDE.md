# 📖 User Guide

## 🎧 Day-to-day TTS

### Speak any text on the screen

1. Highlight text in any app (browser, PDF reader, IDE, Notes…).
2. Press `Cmd ⇧ .` (default — remappable in Preferences).
3. SuperSay reads it aloud through the currently selected voice and speed.
4. `Cmd ⇧ /` pauses/resumes. `Cmd ⇧ ,` stops. `Cmd ⇧ M` exports the last clip to Desktop as a WAV.

### Pick a voice

Eight Kokoro voices ship with SuperSay. Set the default in Preferences → Voice Engine.

| Voice | Style |
| :--- | :--- |
| `af_bella` | American Female — warm, default |
| `af_sarah` | American Female — slightly higher pitch |
| `am_adam` | American Male — clear, conversational |
| `am_michael` | American Male — deep narrative tone |
| `bf_emma` | British Female |
| `bf_isabella` | British Female |
| `bm_george` | British Male |
| `bm_lewis` | British Male |

Most users land on `af_bella` or `am_michael` at 1.1×–1.2× speed for long-form content.

### The Vault — your local history

Every snippet you speak is saved locally in The Vault (sidebar → Library → The Vault). Star important sections to keep them at the top. Nothing in The Vault leaves your Mac.

## 📚 Audiobooks (PDF → narrated audio)

1. Click **Library → Audiobooks**, or drag a PDF onto any SuperSay window.
2. A modal estimates pages, time, and any Gemini cleaning cost. Confirm.
3. SuperSay processes the PDF in the background: cleans each page (Gemini, if you've added a key), generates narration (Kokoro on your Mac), stitches a single seekable WAV with chapter markers.
4. Open the book from the library. Player has: scrub bar, chapter list, sleep timer, live transcript, ambient cover art.
5. Closing the app mid-playback resumes from the last position next time.

### Gemini API key (optional, only for audiobooks)

Audiobook *cleaning* (strip references, normalize line breaks, OCR scanned PDFs) uses Google's Gemini Flash API and requires your own free API key. The key is stored in macOS Keychain — never synced, never sent anywhere except Google's API.

1. Visit <https://aistudio.google.com/apikey>, click **Create API key**, copy.
2. Preferences → Audiobook → paste the key → **Verify**.
3. From now on uploaded PDFs are auto-cleaned. Without a key, audiobooks still work via local heuristics; cleaning is just less aggressive.

You can revoke or rotate the key at any time from the same Google AI Studio page.

## 🔐 Optional sign-in

SuperSay is fully usable without an account. Signing in only links your anonymous usage to a real identity in the public stats. Reasons to sign in:

- You want to show up in the public growth posts.
- You want your audiobook count + audio-hours to persist across reinstalls (future feature — currently sign-in is purely opt-in attribution).

Reasons not to: none, if you'd rather stay anonymous.

To sign in: Preferences → Account → Sign in (Google or email). To leave: same panel, **Sign out**. Anonymous usage continues to be counted (under an opaque UUID stored locally — see PRIVACY.md).

## 🔒 Privacy

Two toggles in Preferences → Privacy:

- **Anonymous Analytics** (default on). When on, the app sends counts only — no text, no file contents, no audio. When off, **zero** requests leave the app. See [PRIVACY.md](../PRIVACY.md) for the full audit.
- **Clean URLs / handles** options (TTS preprocessing — local only, never leaves your Mac).

## 🛠 Troubleshooting

### "Initializing SuperSay…" screen hangs

This means the Swift app cannot talk to the bundled Python backend.

- **Check port:** ensure no other service is using `10101`.
- **Manual reset:** quit SuperSay and run `pkill -f SuperSayServer` in Terminal.
- **Logs:** Preferences → bottom → **Export Debug Logs** to inspect the backend startup trace.

### Text selection is grabbing the wrong text

Some apps (older Chrome, Slack) have slow clipboard response times. SuperSay uses a 250ms buffer. If it fails, click inside the window once before pressing the hotkey.

### Audio pops or clicks

A 50ms linear cross-fade is applied at every sentence boundary. Clicks usually mean the CPU is being throttled. Disable Low Power Mode if you're on a MacBook.

### Apple Music / Spotify isn't ducking

Ducking needs **Automation** permission. System Settings → Privacy & Security → Automation → ensure SuperSay can control "Music" or "Spotify".

### Audiobook upload says "Gemini key required"

Audiobook cleaning uses your Gemini key. Either paste a key in Preferences → Audiobook or use the **Skip cleaning** option to fall back to local heuristics (faster, less accurate on academic PDFs).

### Google sign-in says "Sign-in is not configured"

The macOS app bundle is missing `SuperSayGoogleClientID` in Info.plist. If you're a developer running from source, add your Google OAuth Client ID there (see `docs/setup-v1.1.md`). End-user builds from the official DMG already include this.

### Sign-in opens browser but nothing happens

The browser callback couldn't reach the SuperSay app. Most common cause: a firewall rule blocking 127.0.0.1 traffic. Sign in works on a freshly-installed macOS with default firewall settings.
