# Contributing to SuperSay

We love contributions! Whether you're fixing a bug, adding a new language, or improving the UI, here’s how you can help.

## 🛠️ Development Setup

### 1. Backend

* Install [uv](https://github.com/astral-sh/uv).
* Navigate to `backend/`.
* Download the Kokoro ONNX model and voices binary.
* Run `uv run main.py`.

### 2. Frontend

* Open `SuperSay.xcodeproj` in Xcode 15+.
* Add `KeyboardShortcuts` via Swift Package Manager.

## 📝 Coding Standards

### Swift

* Use **MainActor** for all Store and UI-related classes.
* Follow the **MVVM** pattern used in the project.
* Use **System Symbols** whenever possible for consistent branding.

### Python

* Keep the API lightweight.
* Use **FastAPI** dependency injection.
* Ensure all audio samples are clipped with `np.clip` to prevent hardware distortion.

## 🚀 Pull Request Process

1. Fork the repo and create your branch from `main`.
2. Ensure your code compiles (Run `find . -name "*.swift" | xargs swiftc -parse`).
3. If you changed the API, update `main.py` and the corresponding `fetchAudioChunk` in Swift.
4. Submit your PR with a clear description of the "Why" and "How."

## 📜 Feedback

If you find a bug or have a feature request, please open an issue in the tracker.
