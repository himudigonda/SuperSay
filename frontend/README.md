# SuperSay Frontend (macOS)

The native macOS interface for SuperSay, built with **SwiftUI** and **AppKit**.

## 🏗️ Core Components

### 1. `LaunchManager`
Handles the lifecycle of the local AI engine.
*   **On First Run**: Extracts the embedded `SuperSayServer.zip` to `~/Library/Application Support/SuperSay`.
*   **Startup**: Launches the `SuperSayServer` binary in the background.
*   **Health Check**: Polls the local server until it's ready for inference.

### 2. `AudioService` (The Consumer)
Implements a hardware-synced audio queue.
*   Consumes the HTTP stream from the backend.
*   Schedules PCM buffers on `AVAudioEngine`.
*   Uses `AVAudioPlayerNodeCompletionCallbackType.dataPlayedBack` to accurately track when audio *actually* finishes playing, ensuring perfect sync with UI and Ducking logic.

### 3. `PDFService` (Academic Mode)
A specialized PDF parser for research papers.
*   **Statistical Analysis**: Scans the document to identify and remove repetitive headers/footers.
*   **Cleaning**: Merges hyphenated words and strips academic citations (`[1]`, `(Author, 2023)`).

## 🔨 Building

1.  **Prepare Backend**: Ensure `Resources/SuperSayServer.zip` exists (use `make backend`).
2.  **Open Project**: `SuperSay.xcodeproj`.
3.  **Run**: Build & Run.
