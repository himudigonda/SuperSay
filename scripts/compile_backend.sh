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

# 4. Compile binary with FIXES for FastAPI/AnyIO
# Added specific hidden imports for asyncio/uvicorn internals
echo "🔨 Compiling binary..."
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
    --collect-data "uvicorn" \
    --hidden-import "language_tags" \
    --hidden-import "language_tags.data" \
    --hidden-import "segments" \
    --hidden-import "csvw" \
    --hidden-import "clldutils" \
    --hidden-import "uvicorn.logging" \
    --hidden-import "uvicorn.loops" \
    --hidden-import "uvicorn.loops.auto" \
    --hidden-import "uvicorn.loops.asyncio" \
    --hidden-import "uvicorn.protocols" \
    --hidden-import "uvicorn.protocols.http" \
    --hidden-import "uvicorn.protocols.http.auto" \
    --hidden-import "uvicorn.protocols.http.h11_impl" \
    --hidden-import "uvicorn.lifespan.on" \
    --hidden-import "anyio" \
    main.py

# 5. Verify
if [ -f "dist/SuperSayServer" ]; then
    echo ""
    echo "✅ Compilation Complete!"
    echo "📍 Binary Location: $(pwd)/dist/SuperSayServer"
    echo ""
    echo "👉 Next: Drag 'backend/dist/SuperSayServer' into Xcode Resources."
else
    echo "❌ Error: Compilation failed."
    exit 1
fi
