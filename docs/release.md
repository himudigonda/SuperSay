# 🚀 SuperSay Release Maintenance Guide

This document outlines the standard operating procedure for creating a new versioned release of SuperSay.

## 1. Version Bumping

Before releasing, you must increment the version number in both the backend and frontend components.

### Backend (Python)

Update the `version` field in `backend/pyproject.toml`:

```toml
[project]
name = "backend"
version = "1.0.5" # Update this
```

### Frontend (Xcode)

Update the `MARKETING_VERSION` in the Xcode Project.

1. Open `frontend/SuperSay/SuperSay.xcodeproj`.
2. Select the **SuperSay** project in the sidebar.
3. Under **Targets**, select **SuperSay**.
4. In the **General** tab, update **Version**.

## 2. Git Tagging

Once versions are bumped and committed to `main`:

```bash
# Verify you are on main and up to date
git checkout main
git pull origin main

# Create an annotated tag
git tag -a v1.0.5 -m "Release v1.0.5: Zero Latency Streaming"

# Push the tag to GitHub
git push origin v1.0.5
```

## 3. Building and Packaging
 
 Use the `Makefile` to build the full distribution-ready DMG:
 
 ```bash
 # This builds backend, frontend, injects fonts, and packages the DMG
 make release VERSION=1.0.5
 ```
 
 The output will be: `build/SuperSay-1.0.5.dmg`

## 5. Creating GitHub Release

Use the GitHub CLI (`gh`) to finalize the update:

```bash
gh release create v1.0.5 build/SuperSay-1.0.5.dmg \
    --title "SuperSay v1.0.5 - Zero Latency Streaming" \
    --notes "This update introduces real-time audio streaming, significantly reducing time-to-speech."
```

## ❄️ Pro Tips

- **Always run tests** (`make test`) before tagging.
- Ensure your environment is clean by running `make clean` before a final production build.
- Use annotated tags (`-a`) for releases to include metadata.
