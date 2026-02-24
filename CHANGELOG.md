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
