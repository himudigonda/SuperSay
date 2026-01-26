# 📖 User Guide

## 🎧 Optimizing the Listening Experience
SuperSay is designed for long-form content. For the best experience:
1.  **Voice Selection:** Use `af_bella` or `af_sarah` for a natural female tone, or `am_michael` for a deep narrative tone.
2.  **Speed Control:** Most users prefer `1.1x` or `1.2x` for research papers.
3.  **The Vault:** Every snippet you speak is saved in "The Vault". You can "Star" important sections to build a personalized audio library of insights.

## 🛠 Troubleshooting

### 1. "Initializing SuperSay..." screen hangs
This means the Swift app cannot talk to the Python backend.
-   **Check Port:** Ensure no other service is using port `10101`.
-   **Manual Reset:** Quit the app and run `pkill -f SuperSayServer` in Terminal.
-   **Check Logs:** Use the "Export Debug Logs" button in Preferences to see if the ONNX model failed to load.

### 2. Text Selection is Grabbing the Wrong Text
-   Some apps (like older versions of Chrome or Slack) have slow clipboard response times. SuperSay uses a 250ms buffer. If it fails, try clicking inside the window once before using the shortcut.

### 3. Audio Pops or Clicks
-   SuperSay applies a 50ms linear cross-fade to every sentence. If you hear clicks, the CPU might be throttling. Ensure you are not in "Low Power Mode" on your MacBook.

### 4. Apple Music isn't Ducking
-   Ducking requires **Automation** permissions. If it isn't working, go to **System Settings > Privacy & Security > Automation** and ensure SuperSay has access to "Music" or "Spotify".
