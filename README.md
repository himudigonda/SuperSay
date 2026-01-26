# 🎙️ SuperSay

> **Turn any text on your Mac into cinematic, ultra-realistic AI speech.**

![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=for-the-badge&logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-Native-007AFF?style=for-the-badge&logo=apple&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11+-3776AB?style=for-the-badge&logo=python&logoColor=white)

**SuperSay** is a professional-grade text-to-speech utility for macOS. It runs the state-of-the-art Kokoro model locally to generate human-like speech with zero latency.

---

## ⚠️ Important: First-Time Setup

Because SuperSay is currently an **Independent, Unsigned** project, macOS will apply strict security blocks. Follow these steps to get started:

### 1. Bypass "App is Damaged" (Gatekeeper)
When you first move the app to `/Applications`, macOS may say it is "damaged." This is just because it isn't notarized.
- **Option A:** Right-click `SuperSay.app` in your Applications folder and select **Open**. Click **Open** again on the dialog.
- **Option B:** Run this command in Terminal:
  ```bash
  xattr -cr /Applications/SuperSay.app
  ```

### 2. Fix "Speak Selection" (Accessibility)
If the global shortcut (`Cmd+Shift+.`) doesn't grab text:
1. Go to **System Settings > Privacy & Security > Accessibility**.
2. Remove SuperSay with the **minus (-)** button.
3. Restart SuperSay and grant permission when prompted.
4. If it still fails, run this reset command:
   ```bash
   tccutil reset Accessibility com.himudigonda.SuperSay
   ```

---

## ✨ Key Features
* **🔒 100% Offline**: No data leaves your Mac.
* **⚡️ Zero-Latency**: Audio starts instantly via parallel inference streaming.
* **🎓 Academic Mode**: Specialized cleaning for research papers (removes citations/headers).
* **🎬 Cinematic Ducking**: Automatically lowers Music/Spotify volume while speaking.

## 🛠 Build from Source
```bash
git clone https://github.com/himudigonda/SuperSay.git
cd SuperSay
make run
```

## 🤝 Contributing
We are looking for help with:
- **Notarization Pipeline**: Implementing an automated signing flow.
- **CoreAudio Integration**: Moving from AppleScript ducking to native system audio taps.
- **UI/UX**: Refined visualizers and theme support.

[Check the Contributing Guide](docs/CONTRIBUTING.md)
