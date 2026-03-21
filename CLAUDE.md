# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SuperSay is a macOS text-to-speech application that runs fully on-device using the Kokoro-82M ONNX model. A SwiftUI frontend communicates with a Python/FastAPI backend via HTTP streaming on `localhost:10101`. The backend is compiled into a standalone binary via PyInstaller and bundled inside the Swift app.

## Common Commands

All top-level tasks go through `make`:

```bash
make setup               # Install Python deps (uv) and configure git hooks
make backend             # Compile Python → PyInstaller binary (SuperSayServer)
make app                 # Build macOS app with Xcode
make run                 # Full pipeline: backend + app + launch
make lint                # Ruff + Black (Python), SwiftLint (Swift)
make format              # Auto-format with Ruff, Black, SwiftFormat
make test                # pytest (backend) + Xcode tests (frontend)
make benchmark           # Run performance profiler + generate reports
make release VERSION=x.y.z  # Full release build → DMG
make clean               # Remove build artifacts
make nuke                # Complete factory reset (app data + permissions)
```

**Backend tests only:**
```bash
cd backend && uv run pytest -v
cd backend && uv run pytest tests/test_tts.py -v   # Single test file
```

**Frontend tests:** `Cmd+U` in Xcode, or `make test`.

## Architecture

### Runtime Communication
The Swift app (`LaunchManager.swift`) extracts a bundled `SuperSayServer.zip` to `~/Library/Application Support/SuperSayServer/` on first launch, then starts the backend process. `BackendService.swift` manages the process lifecycle and sends HTTP requests to it.

### Inference Pipeline (Zero-Latency Streaming)
`POST /speak` → `TTSEngine` splits text into sentences (regex on punctuation) → sentences are phonemized and run through ONNX Kokoro-82M sequentially (single `ThreadPoolExecutor(max_workers=1)` to prevent espeak-ng C-level race conditions) → PCM chunks are yielded as a `StreamingResponse` → `AudioService.swift` (AVAudioEngine) schedules buffers as they arrive while earlier chunks are already playing.

Key constraint: **inference must remain sequential** despite the async streaming architecture. Parallel task scheduling corrupts the espeak-ng phonemizer.

### Key Files

| File | Role |
|------|------|
| `backend/app/services/tts.py` | `TTSEngine`: sentence splitting, sequential inference, fade injection |
| `backend/app/services/audio.py` | `AudioService`: PCM encoding, 16-bit clipping, fade curves |
| `backend/app/api/endpoints.py` | `/health` (model readiness) and `/speak` (streaming) routes |
| `backend/app/core/config.py` | Settings with PyInstaller resource-path handling |
| `frontend/.../Services/LaunchManager.swift` | Extracts and starts the backend binary |
| `frontend/.../Services/BackendService.swift` | HTTP streaming client, process manager |
| `frontend/.../Services/AudioService.swift` | AVAudioEngine playback, hardware-synced progress callbacks |
| `frontend/.../ViewModels/DashboardViewModel.swift` | Central state (voice, speed, status) |
| `frontend/.../Utilities/Shortcuts.swift` | Global hotkey registration (Cmd+Shift+.) |

### Model Files (not in git)
`backend/kokoro-v1.0.onnx` (326 MB) and `backend/voices-v1.0.bin` (28 MB) must be present locally for backend development. They are bundled into the PyInstaller binary at `make backend` time.

## Tech Stack

- **Backend:** Python 3.11, FastAPI, kokoro-onnx, uvicorn, uv (package manager)
- **Frontend:** Swift 6, SwiftUI, AVFoundation (AVAudioEngine), AppKit, Combine
- **Build:** PyInstaller for backend binary, Xcode 15+ for app
- **Linting:** Ruff + Black (Python, 88-char lines, py311 target), SwiftLint (`.swiftlint.yml`)

## Release Process

See `docs/release.md`. The short version: `make release VERSION=x.y.z` compiles the backend binary, builds the Xcode app in Release config, and packages a DMG. `make ship VERSION=x.y.z` additionally tags and uploads to GitHub.
