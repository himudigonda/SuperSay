# SuperSay Frontend (macOS)

The native macOS interface for SuperSay, built with **SwiftUI** and **AppKit**.

## 📂 Project Structure

*   `Core/`: Non-UI logic (AudioEngine, HistoryManager, Process Management).
*   `Views/`: SwiftUI Views (Dashboard, Settings, Vault).
*   `Resources/`: Contains the compiled Python backend (`SuperSayServer`).

## 🔑 Key Technologies

*   **KeyboardShortcuts**: For global hotkey detection (`Cmd+Shift+.`).
*   **ServiceManagement**: For "Launch at Login" functionality.
*   **AppSandbox**: *Note: The App Sandbox is currently DISABLED to allow AppleScript control of Music/Spotify.*

## 🔨 Building

1.  Open `SuperSay.xcodeproj`.
2.  Ensure the backend has been compiled and placed in `Resources/`.
3.  Build and Run.
