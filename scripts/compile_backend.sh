#!/bin/bash
set -e

echo "🚀 Starting Backend Compilation..."
cd backend

# 1. Setup Env
if ! command -v uv &> /dev/null; then
    echo "❌ Error: 'uv' is not installed."
    exit 1
fi
uv sync

# 2. Install PyInstaller
echo "🔧 Installing PyInstaller..."
uv pip install pyinstaller

# 3. FIND ALL MISSING DATA DIRECTORIES
echo "🔍 Locating all required data directories..."

ESPEAK_PATH=$(uv run python -c "import os, espeakng_loader; print(os.path.dirname(espeakng_loader.__file__))")
echo "   ✓ espeakng_loader: $ESPEAK_PATH"

# 4. Compile with --collect-data for all problematic packages
echo "🔨 Compiling binary with explicit data collection..."
uv run pyinstaller --clean --noconsole --onefile --noconfirm --name "SuperSayServer" \
    --add-data "kokoro-v1.0.onnx:." \
    --add-data "voices-v1.0.bin:." \
    --add-data "$ESPEAK_PATH:espeakng_loader" \
    --collect-data "language_tags" \
    --collect-data "segments" \
    --collect-data "csvw" \
    --collect-data "kokoro_onnx" \
    --collect-data "phonemizer" \
    --collect-data "clldutils" \
    --hidden-import "language_tags" \
    --hidden-import "language_tags.data" \
    --hidden-import "segments" \
    --hidden-import "csvw" \
    --hidden-import "clldutils" \
    main.py

# 5. Verify
if [ -f "dist/SuperSayServer" ]; then
    echo ""
    echo "✅ Compilation Complete!"
    echo "📍 Binary Location: $(pwd)/dist/SuperSayServer"
    echo ""
    echo "👉 Next: Drag 'backend/dist/SuperSayServer' into Xcode."
else
    echo "❌ Error: Compilation failed."
    exit 1
fi
