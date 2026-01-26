# Contributing to SuperSay

## 🎯 Current Priorities

We are prioritizing the following engineering tasks:

1.  **Code Signing/Notarization:** We need a robust GitHub Action to automate the Apple Developer signing process so users don't have to use `xattr`.
2.  **Native Audio Taps:** Replacing the current AppleScript-based ducking with native `CoreAudio` or `AudioKit` taps for smoother volume transitions.
3.  **Model Management:** Moving models out of the app bundle and into an on-demand downloader (CDN) to reduce initial download size.

## 🛠 Workflow

-   **Backend:** Managed by `uv`. Python 3.11+.
-   **Frontend:** SwiftUI. Minimum target macOS 14.0 (Sonoma).
-   **Communication:** All communication happens via local HTTP streaming on port `10101`.

## 🧪 Testing

Before submitting a PR, ensure all tests pass:

```bash
# Backend
cd backend && uv run pytest

# Frontend (Logic)
# Run via Xcode (Cmd+U) or:
make test-frontend
```

Please follow the **Ruff** (Python) and **SwiftLint** (Swift) style guides included in the repository.
