### 🚀 SuperSay v2.0.0 Changelog

#### 🔐 Accounts + Analytics (new)
*   **Optional sign-in** — Google OAuth (desktop loopback + PKCE) and email/password via Supabase Auth. App works identically signed-in or anonymous.
*   **5-step onboarding** with a transparent privacy nudge: "we count you, never read your text." Skip always available.
*   **Counts-only telemetry**, defense-in-depth — closed props whitelist enforced on client AND server. `text`, `email`, and any unknown keys are dropped before HTTP serialization; the server re-validates before insert. Raw text, file contents, and audio never cross the network boundary.
*   `MetricsService` v2: batched outbox (20 events / 30s), persisted across restarts in `UserDefaults`, Bearer-when-signed + anon_id-always, hard kill switch via `telemetryEnabled` toggle.
*   **Public metrics dashboard** at the metrics site — total users, DAU/WAU, generations, audio-hours, voice distribution, D1/D7/D30 retention cohorts, audiobook funnel. All reads from nightly daily rollups; never raw events.
*   `PRIVACY.md` with `file:line` audit trail — every byte that leaves the Mac is documented with a reference into the code.
*   `docs/specs/accounts-analytics.md` + `docs/analytics.md` + `docs/setup-v1.1.md` deploy checklist.

#### 📚 Audiobook Feature
*   Full PDF-to-audiobook pipeline: upload PDF → Gemini 1.5 Flash cleans text → Kokoro/KittenTTS narrates → single seekable WAV with chapter markers.
*   Audible-style player: scrub bar, chapter list, sleep timer, live transcript, cover art with ambient gradient.
*   **OCR for scanned PDFs:** image-only pages now automatically processed via Gemini vision — no more 422 rejections.
*   Per-page resumability; interrupted books resume at the last completed page.

#### 🤖 AI / Backend
*   **Migrated to `google-genai` 2.0.0** (replaces deprecated `google-generativeai`). All calls use native async (`client.aio`).
*   Section detection via Gemini; falls back to PDF outline bookmarks when available.
*   SQLite (WAL mode) metadata store — replaces per-book `meta.json`; auto-migrates on startup.
*   **Structured JSON logging** on every backend log line, with a request correlation id propagated via `X-Correlation-ID` header. Replaces ad-hoc `print()` calls; no new dependencies (stdlib only).
*   93 backend tests passing.

#### 🏎️ TTS Engine
*   KittenTTS nano/micro/mini variants with lookahead inference cache (sub-20ms cache-hit TTFA).
*   Removed `allow_spinning=1` — fixes 800-900% idle CPU on Apple Silicon.
*   `audio_seconds` metric is sourced from `AudioService`'s rendered PCM frame count, not estimated — accurate to the millisecond.

#### 🖥️ macOS UI
*   NavigationStack-based audiobook player (keyboard shortcuts, sidebar stays visible).
*   Preferences: Gemini key verify, per-book voice/speed defaults, **new Account section** (signed-in email + sign out, or sign-in CTA when anonymous).
*   NowPlayingBar / Continue Listening, global drag-and-drop PDF entry point.
*   Smooth TTS preemption fade (120ms) when hotkey fires during audiobook playback.

#### 🗄️ Backend & API (`himudigonda.me`)
*   New endpoints: `POST /api/supersay/events` (telemetry ingest), `POST /api/supersay/auth/{google,email/signup,email/login,email/request-reset,email/confirm-reset,link-anon}`, `GET /api/supersay/metrics/{overview,daily,voices,retention,audiobook}`.
*   Supabase schema: `supersay_users`, `supersay_events`, `supersay_daily_rollups` + `supersay_retention_cohorts` view + `compute_supersay_rollup()` function. RLS locks the user list to service-role only.
*   Nightly Vercel cron at 03:15 UTC computes daily rollups; idempotent on re-run.
*   In-memory token-bucket rate limiting: 60/min on `/events`, 5/min on `/auth/*`.
*   Normalized error shape `{error: {code, message}}` across every `/api/supersay/*` route — no stack-trace leaks.
*   Legacy `/api/telemetry` softened to log+drop so installed v1.x clients keep working silently during migration.

#### 📦 Build
*   PyInstaller cleanup: removed stale `google.ai` and `google.api_core` flags that caused harmless but noisy warnings.
*   `create_dmg.sh` now auto-detects Xcode.app so builds no longer fail when `xcode-select` points to CommandLineTools.

---

### 🚀 SuperSay v1.1.0 Changelog

#### 📚 Audiobook Feature (New)
*   **Full PDF-to-Audiobook Pipeline:** Upload any PDF → Gemini 1.5 Flash cleans text for narration → Kokoro/KittenTTS generates per-page audio → single WAV with chapter markers.
*   **Audible-style Player:** Scrub bar, chapter list, sleep timer, live transcript panel, cover art with ambient gradient.
*   **OCR for Scanned PDFs:** Image-only PDFs (previously rejected) are now processed via Gemini vision — pages with < 50 extractable chars are automatically OCR'd and cleaned in one Gemini call.
*   **Resumability:** Each phase checkpoints to disk; interrupted books resume at the last completed page. Handles API key rotation via "needs_key" state.
*   **Interactive TTS Preemption:** Pressing the hotkey mid-generation pauses audiobook at the next page boundary, runs TTS, then resumes — no conflicts.
*   **SQLite Metadata:** Per-book meta.json replaced with a single WAL-mode SQLite DB; auto-migrates legacy files on startup.

#### 🤖 AI Improvements
*   **google.genai SDK (v2.0.0):** Migrated from deprecated `google-generativeai` to `google-genai`. All Gemini calls now use native async (`client.aio`) — no more `asyncio.to_thread` wrappers.
*   **Section Detection:** Gemini identifies chapter/section boundaries from cleaned text; falls back to PDF outline bookmarks if present.

#### 🏎️ TTS Engine
*   **KittenTTS Integration:** Full multi-variant support (nano/micro/mini) with lookahead inference cache for sub-20ms cache-hit TTFA.
*   **Engine Switching at Runtime:** Switch between Kokoro and KittenTTS without restart; active streams drain cleanly first.
*   **CPU Fix:** Removed `allow_spinning=1` from ORT SessionOptions that caused 800-900% CPU idle load.

#### 🖥️ macOS Frontend
*   **NavigationStack Player:** Audiobook player opens as a navigation push (not sheet), keeping the sidebar visible and enabling keyboard shortcuts.
*   **Preferences:** Gemini API key with live verification, default audiobook voice/speed, font selector.
*   **NowPlayingBar:** Persistent mini-player for Continue Listening without opening the full player.
*   **Smooth Preemption:** Audiobook playback fades out over 120ms when TTS hotkey fires (no click/pop).

#### 📦 Build & Infrastructure
*   **Version Bump:** 1.0.6 → **1.1.0**.
*   **PyInstaller:** Updated to collect `google.genai`, `pdfplumber`, `pypdfium2`, `PIL`, `kittentts`.
*   **81 Backend Tests:** Covers upload, OCR routing, resume, coordinated delete, range requests, SSE events, cost math.

---

### 🚀 SuperSay v1.0.6 Changelog

#### 🧠 Core Engine (Backend)
*   **Fixed Audio Artifacts (Screeching/Popping):** Implemented unconditional clipping in `AudioService` to prevent 16-bit integer overflow when model output slightly exceeds 1.0 amplitude.
*   **Fixed Thread Safety & Word Skipping:** Completely removed `asyncio.to_thread`. The engine now uses a dedicated `ThreadPoolExecutor(max_workers=1)` to serialize all `espeak-ng` calls, preventing C-level memory corruption that caused sentences to be trimmed or skipped.
*   **Sequential Generation:** Switched from `asyncio.create_task` (parallel queueing) to a strict sequential loop to prevent overwhelming the phonemizer.
*   **Smoother Audio Transitions:** Adjusted fade logic. The first sentence now preserves its "attack" (no fade-in), while subsequent sentences fade in gently to prevent clicks.

#### 🖥️ MacOS Frontend
*   **Fixed "Ghost Playback":** The progress bar and timer now sync directly with `AVAudioNode` hardware render time instead of using a system clock. The UI now pauses instantly if the audio engine buffers or starves.
*   **Fixed "Hostreet" Bug:** Updated `TextProcessor` to use Regex Word Boundaries (`\b`). Abbreviations like "st." will no longer trigger inside words (e.g., "host." will no longer become "hostreet").
*   **Fixed Missing Logs:** Modified `LaunchManager` to delete only the `SuperSayServer` binary directory during updates, preserving the application logs (`frontend.log`, `backend.log`) for debugging.
*   **Empty State Handling:** Added `togglePlayback()` logic. Pressing Play (UI or Shortcut) when no text is loaded now displays a helpful error message instead of silently running the timer.

#### 📦 Build & Infrastructure
*   **"Nuclear" Build Script:** Completely rewrote `scripts/compile_backend.sh`. It now manually locates and injects `config.json` into the PyInstaller bundle to fix the `FileNotFoundError` preventing backend startup.
*   **Version Bump:** Project updated to **1.0.6**.
