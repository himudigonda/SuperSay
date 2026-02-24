#!/bin/bash
set -e
echo "🚀 STARTING NUCLEAR BACKEND BUILD..."

# 1. Cleanup
pkill -9 SuperSayServer || true
rm -rf backend/dist backend/build
rm -f frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip

cd backend
# Ensure venv exists
uv sync

# 2. LOCATE CRITICAL ASSETS
PYTHON_EXEC="./.venv/bin/python"
ESPEAK_PATH=$($PYTHON_EXEC -c "import os, espeakng_loader; print(os.path.dirname(espeakng_loader.__file__))")
KOKORO_CONFIG=$($PYTHON_EXEC -c "import os, kokoro_onnx; print(os.path.join(os.path.dirname(kokoro_onnx.__file__), 'config.json'))")

echo "📍 Config located at: $KOKORO_CONFIG"

# 3. COMPILE
# We remove hidden-import kokoro_onnx to let PyInstaller find it naturally first,
# then we surgically repair the missing config.
$PYTHON_EXEC -m PyInstaller --clean --noconsole --onedir --noconfirm --name "SuperSayServer" \
    --paths . \
    --add-data "kokoro-v1.0.onnx:." \
    --add-data "voices-v1.0.bin:." \
    --add-data "$ESPEAK_PATH:espeakng_loader" \
    --collect-all "phonemizer" \
    --collect-all "language_tags" \
    --collect-all "kokoro_onnx" \
    --hidden-import "uvicorn.loops.asyncio" \
    --hidden-import "uvicorn.protocols.http.h11_impl" \
    --hidden-import "fastapi" \
    --hidden-import "starlette" \
    app/main.py

# 4. SURGICAL INJECTION (Double Check)
# Even with collect-all, we force copy config.json if it's missing to be 100% sure.
DEST_DIR="dist/SuperSayServer/_internal/kokoro_onnx"
if [ ! -f "$DEST_DIR/config.json" ]; then
    echo "💉 Manual injection of config.json required..."
    mkdir -p "$DEST_DIR"
    cp "$KOKORO_CONFIG" "$DEST_DIR/"
else
    echo "✅ config.json was collected automatically."
fi

# 5. ZIP AND MOVE
echo "📦 Zipping backend..."
cd dist
zip -r -q SuperSayServer.zip SuperSayServer
cd ..

echo "📦 Installing to Resources..."
mkdir -p ../frontend/SuperSay/SuperSay/Resources/
mv dist/SuperSayServer.zip ../frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip

echo "✅ Nuclear Build Complete."
