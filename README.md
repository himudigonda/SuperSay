# 🎙️ SuperSay

> **Turn any text on your Mac into cinematic, ultra-realistic AI speech.**

<p align="center">
  <img src="assets/SuperSay_Light.png" width="45%" alt="SuperSay Light Mode" />
  &nbsp; &nbsp;
  <img src="assets/SuperSay_Dark.png" width="45%" alt="SuperSay Dark Mode" />
</p>

![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=for-the-badge&logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-Native-007AFF?style=for-the-badge&logo=apple&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0-F05138?style=for-the-badge&logo=swift&logoColor=white)
![TTS Engine](https://img.shields.io/badge/TTS_Engine-Kokoro--82M-blueviolet?style=for-the-badge)
![Model Format](https://img.shields.io/badge/Model_Format-ONNX-00529B?style=for-the-badge&logo=onnx&logoColor=white)

**SuperSay** is a professional-grade text-to-speech utility for macOS. It runs the state-of-the-art [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M) model locally on your device to generate human-like speech.

---

## ✨ Key Features

*   **🔒 100% Offline & Private**: No data leaves your Mac. The AI model runs locally on your Apple Silicon chip.
*   **🎓 Academic Mode**: A specialized engine for reading research papers. It automatically strips citations, merges hyphenated words, and removes repetitive headers/footers for a smooth listening experience.
*   **⚡️ Zero-Latency Streaming**: Audio starts playing instantly via a hardware-synced producer-consumer pipeline. No waiting for long documents to render.
*   **🎬 Cinematic Audio Engine**: Intelligently "ducks" your Music or Spotify volume while speaking and fades it back in when done.
*   **📦 Searchable History**: Revisit anything you've listened to in "The Vault".

## 🏗️ Architecture (Zipped Deployment)

SuperSay uses a unique **Self-Extracting Sidecar** architecture to be distribution-friendly.

1.  **Build**: The Python backend + AI Models are compiled and Zipped into the app bundle.
2.  **Launch**: On first run, the app extracts the engine to `~/Library/Application Support/`.
3.  **Run**: The Swift frontend communicates with this local engine via high-speed HTTP streaming.

[**Read the Architecture Deep Dive ->**](docs/architecture.md)

## 🚀 Quick Start

### Installation

**Option 1: Download Release**
Grab the latest `.dmg` from the [Releases Page](https://github.com/himudigonda/SuperSay/releases).

**Option 2: Build from Source**

1.  **Clone**:
    ```bash
    git clone https://github.com/himudigonda/SuperSay.git
    cd SuperSay
    ```

2.  **Build**:
    ```bash
    # This automates dependency setup, backend compilation, and app packaging
    make run
    ```

## 📚 Documentation

*   [**Architecture Deep Dive**](docs/architecture.md): How the Producer-Consumer streaming works.
*   [**User Guide**](docs/USER_GUIDE.md): Keyboard shortcuts and features.
*   [**Backend Details**](backend/README.md): API and Model technicals.
*   [**Frontend Details**](frontend/README.md): SwiftUI architecture.
*   [**Contributing**](docs/CONTRIBUTING.md): How to build and submit PRs.

---
<p align="center">Made with ❤️ for the macOS Community</p>
