# 🗺️ SuperSay Roadmap

Sprint tracking: see [`SPRINTS.md`](./SPRINTS.md) (Sprint 1 — Accounts + Analytics + Onboarding shipped in v2.0.0).

## 🟢 Phase 1 — Core Engine (Complete, v1.0)

- [x] Local Kokoro-82M ONNX inference (on-device, eight voices).
- [x] Zero-latency async streaming.
- [x] Global hotkeys (`Cmd ⇧ .` and friends, remappable).
- [x] The Vault — local TTS history with starring.

## 🟢 Phase 2 — Audiobooks + Productivity (Complete, v1.1)

- [x] PDF → audiobook pipeline (Gemini cleaning + Kokoro narration + chapter markers + transcript).
- [x] Audible-style player (scrub bar, sleep timer, Continue Listening, NowPlayingBar).
- [x] OCR for image-only PDFs via Gemini vision.
- [x] SQLite (WAL-mode) audiobook store with per-page resumability.
- [x] TTS preemption fade (audiobook gracefully duck-stops when hotkey TTS fires).

## 🟢 Phase 3 — Accounts + Analytics + Onboarding (Complete, v2.0)

- [x] Optional sign-in: Google OAuth (desktop loopback + PKCE) and email/password via Supabase Auth.
- [x] 5-step onboarding with transparent sign-in nudge.
- [x] `MetricsService` v2 — batched counts-only outbox, closed props whitelist, persisted across restarts, hard kill switch via `telemetryEnabled`.
- [x] Public metrics dashboard (DAU/WAU, audio-hours, voice distribution, retention cohorts, audiobook funnel).
- [x] `PRIVACY.md` with `file:line` audit trail.
- [x] Structured JSON backend logging with per-request correlation id.

## 🟡 Phase 4 — Reach (Planned)

- [ ] **Native Safari/Chrome Extension** — one-click "send to SuperSay".
- [ ] **Code-signing + notarization** — eliminate the `xattr` workaround for end users (requires paid Apple Developer membership).
- [ ] **Sign in with Apple** — once code-signing lands.
- [ ] **Per-user audiobook sync** — optional cross-device library when signed in.

## 🔴 Phase 5 — Advanced (Speculative)

- [ ] **Voice cloning:** 10-second sample → custom voice.
- [ ] **iOS companion:** listen to The Vault and audiobooks on the go.
- [ ] **CoreAudio ducking:** replace AppleScript ducking with a native audio tap for smoother volume transitions.
