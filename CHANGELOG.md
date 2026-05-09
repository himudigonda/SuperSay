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
