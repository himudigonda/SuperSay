# Contributing to SuperSay

## 🎯 Current Engineering Goals
We are specifically looking for Pull Requests in these areas:

### 1. Security & Notarization (High Priority)
Currently, users must manually bypass Gatekeeper. We need a GitHub Action workflow that:
- Code signs the binary with a Developer ID.
- Submits the app to Apple's Notarization service (`xcrun altool`).

### 2. Native Audio Taps
Our current Music Ducking uses AppleScript. This is "hacky" and requires Automation permissions. We want to move to **CoreAudio/AudioKit** to intelligently duck system audio at the buffer level.

### 3. Local Model Management
The 80MB ONNX model is currently zipped inside the app. We want to move to an on-demand downloader that verifies checksums and stores models in `Application Support`.

## 🛠 Development Workflow
1. **Backend**: Python logic is in `backend/app`. Use `uv` for management.
2. **Frontend**: SwiftUI logic is in `frontend/SuperSay`.
3. **The Bridge**: The communication is HTTP Streaming. Do not block the main thread.

Run `make help` to see all available automation commands.
