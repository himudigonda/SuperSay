# 🎙️ SuperSay

**The Ultimate AI Voice Utility for macOS.**

SuperSay is a professional, set-and-forget utility that transforms any text on your screen into ultra-realistic AI speech. Built with a focus on cinematic audio quality, smooth system integration, and high-performance parallel processing.

![SuperSay Banner](https://img.shields.io/badge/macOS-14.0+-blue?style=for-the-badge&logo=apple)
![FastAPI](https://img.shields.io/badge/FastAPI-005571?style=for-the-badge&logo=fastapi)
![SwiftUI](https://img.shields.io/badge/SwiftUI-007ACC?style=for-the-badge&logo=swift)

---

## ✨ Key Features

### 🎬 Cinematic Audio Environment

*   **Smart Music Ducking**: Automatically fades your Music or Spotify volume down to 10% when speaking and glides it back up with a 1-second "cinematic buffer."
*   **Zero-Overlap Logic**: Ensures the AI never battles your music. It waits for the fade-down to complete before the first word is spoken.
*   **Digital Boost**: Includes a digital gain stage allowing for up to **150% volume amplification** without distortion.

### 🧠 High-Performance Extraction

*   **Parallel Generation Pipeline**: Splits long articles into sentences and generates audio in parallel via a Python backend.
*   **Binary Header Patching**: Manually reconstructs WAV headers to merge parallel chunks into a single, seamless track—perfect for long-form reading.
*   **Intelligent Text Purification**: Strips bullet points, URLs, and non-text artifacts to prevent TTS engine crashes.

### 🌎 Global Intelligence

*   **Auto-Language Detection**: Uses Apple's `NaturalLanguage` framework to instantly detect and switch between English, French, Japanese, and Chinese.
*   **The Vault**: A searchable, starred history of everything you've ever "SuperSaid." Never lose a great snippet again.
*   **Native Integration**: Secure modern "Launch at Login" support and centralized system environment controls.

---

## 🛠️ Tech Stack

### Frontend (macOS)

*   **SwiftUI**: For a modern, glassmorphic dashboard.
*   **AVFoundation**: High-fidelity audio playback and session management.
*   **ServiceManagement**: For secure, modern "Launch at Login" items.
*   **KeyboardShortcuts**: Native global hotkey registration.

### Backend (Python/TTS)

*   **FastAPI**: Ultra-fast asynchronous REST API.
*   **Kokoro v1.0**: The state-of-the-art ONNX-based TTS model.
*   **SoundFile & NumPy**: High-performance audio signal processing.
*   **uv**: Blazing fast Python package management.

---

## 🚀 Getting Started

### 1. Backend Setup (Local Server)

SuperSay requires a local AI engine running on port 8000.

```bash
cd backend
# Install dependencies and start the server
uv run main.py
```

*Note: Ensure `kokoro-v1.0.onnx` and `voices-v1.0.bin` are in the backend folder.*

### 2. Frontend Setup (Xcode)

1. Open `SuperSay.xcodeproj`.
2. Ensure you have the `KeyboardShortcuts` package added as a dependency.
3. Build and Run (**Cmd+R**).

### 3. Distribution (Public Release)

To package the app for others, use the provided compilation script:

```bash
chmod +x scripts/compile_backend.sh
./scripts/compile_backend.sh
```

Then drag the resulting binary into the Xcode **Resources** folder. The app will now auto-launch the backend on start.

---

## ⌨️ Shortcuts

### 🎧 Playback Controls

| Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Speak Selection** | `⌘` `⇧` `.` | Reads the currently selected text. |
| **Pause / Resume** | `⌘` `⇧` `/` | Pauses the AI mid-sentence or resumes playback. |
| **Stop** | `⌘` `⇧` `,` | Instantly stops playback and resets the progress. |

### 💾 Exporting

| Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Export to Desktop** | `⌃` `⌘` `⇧` `/` | Generates audio and saves it as a `.wav` file to your Desktop. |

---

## 🏗️ Architecture

SuperSay uses a **Producer-Consumer** model for audio:

1. **Swift** captures selection -> **Python** receives text.
2. **FastAPI** splits text into chunks and runs parallel inference.
3. **Swift** receives chunks, strips headers, and performs **Binary Patching** to create a master WAV.
4. **AudioEngine** manages the hardware layer and system volume ducking.

---

## 📜 License & Contribution

This project is licensed under the **MIT License**. We welcome contributions focused on new voice models and browser-specific integration.

---

**Developed by Himansh Mudigonda**

[GitHub](https://github.com/himudigonda) | [LinkedIn](https://www.linkedin.com/in/himudigonda)

**Made by Professionals, for Professionals.**
