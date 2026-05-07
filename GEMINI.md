# SuperSay Project Context

SuperSay is a high-performance, local-first Text-to-Speech (TTS) application for macOS. It uses a hybrid architecture combining a native **SwiftUI** frontend with a **Python/FastAPI** backend that runs inference using the **Kokoro-82M ONNX** model.

## 🏗️ Architecture

### Hybrid Model
- **Frontend (SwiftUI):** Manages the macOS lifecycle, global hotkeys, accessibility permissions, and audio playback using `AVAudioEngine`. It consumes a chunked WAV stream from the backend.
- **Backend (Python/FastAPI):** Acts as the inference engine. It uses `kokoro-onnx` for high-quality, zero-latency speech generation. It is bundled as a standalone binary (`SuperSayServer`) using PyInstaller for distribution.

### Audio Pipeline (Producer-Consumer)
1. **Producer:** The Python backend splits text into semantic chunks and generates PCM data. It yields a 44-byte WAV header followed by streaming PCM chunks.
2. **Consumer:** `AudioService.swift` receives binary data via `URLSessionDataDelegate`, strips the header, accumulates samples, and schedules them into `AVAudioPCMBuffer` for `AVAudioEngine`.

## 🛠️ Building and Running

The project uses a `Makefile` to automate all workflows.

### Prerequisites
- macOS 14.0+
- Apple Silicon (Native)
- Python 3.11+
- `uv` (Python package manager)
- Xcode & Command Line Tools

### Key Commands
- **Setup:** `make setup` (Installs Python dependencies via `uv` and sets up git hooks).
- **Run:** `make run` (Builds the backend, then the app, and launches it).
- **Test:** `make test` (Runs Python `pytest` and Swift `xcodebuild` tests).
- **Lint/Format:** `make lint` and `make format` (Ruff/Black for Python, SwiftLint/SwiftFormat for Swift).
- **Full Reset:** `make nuke` (Cleans build artifacts and resets macOS accessibility permissions).
- **Release:** `make release VERSION=x.y.z` (Generates a distribution DMG).

## 📂 Project Structure

- `frontend/SuperSay/`: SwiftUI source code.
    - `Services/`: Core logic (Audio, Backend process management).
    - `Views/`: SwiftUI components and layouts.
- `backend/`: Python inference engine.
    - `app/api/`: FastAPI routes (`/speak`, `/health`).
    - `app/services/`: Core TTS and Audio processing logic.
- `scripts/`: Automation scripts for builds, benchmarks, and releases.
- `docs/`: Technical documentation (Architecture, Roadmap, User Guide).

## 📝 Development Conventions

### Python Backend
- **Dependencies:** Managed via `uv` in `backend/pyproject.toml`.
- **Styling:** Follows PEP 8, enforced by `ruff` and `black`.
- **Inference:** Uses a dedicated `ThreadPoolExecutor(max_workers=1)` for `espeak-ng` safety and consistent C-thread execution.

### Swift Frontend
- **Async/Await:** Preferred for networking and service calls.
- **State Management:** Uses `@StateObject` and `ObservableObject` for service-level state.
- **Shortcuts:** Managed via the `KeyboardShortcuts` package.
- **UI:** Custom Poppins fonts are registered at runtime from the app bundle.

## ⚡️ Key Features for Reference
- **Zero-Latency:** Audio starts in <200ms by streaming chunks before the full text is processed.
- **Cinematic Ducking:** Lowers system media volume during playback.
- **Global Shortcuts:** 
    - `Cmd + Shift + .`: Speak Selection
    - `Cmd + Shift + /`: Play/Pause
    - `Cmd + Shift + ,`: Stop
    - `Cmd + Shift + M`: Export to Desktop
