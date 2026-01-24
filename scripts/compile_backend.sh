#!/bin/bash
# Compiles the Python backend into a standalone macOS binary

echo "🚀 Starting Backend Compilation..."

# 1. Ensure PyInstaller is installed
uv pip install pyinstaller

# 2. Compile using PyInstaller with bundled data
uv run pyinstaller --onefile --noconsole --name "SuperSayServer" \
    --add-data "backend/kokoro-v1.0.onnx:." \
    --add-data "backend/voices-v1.0.bin:." \
    backend/main.py

echo "✅ Compilation Complete! Binary saved to ./dist/SuperSayServer"
echo "👉 NEXT STEP: Drag ./dist/SuperSayServer into your Xcode project's 'Resources' folder."
