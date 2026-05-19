#!/bin/bash
set -e
echo "🚀 STARTING BACKEND BUILD..."

# 1. Cleanup
pkill -9 SuperSayServer || true
rm -rf backend/dist backend/build
rm -f frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip

cd backend
# Ensure venv exists and is up to date
uv sync

# 2. LOCATE CRITICAL ASSETS
PYTHON_EXEC="./.venv/bin/python"
ESPEAK_PATH=$($PYTHON_EXEC -c "import os, espeakng_loader; print(os.path.dirname(espeakng_loader.__file__))")
KOKORO_CONFIG=$($PYTHON_EXEC -c "import os, kokoro_onnx; print(os.path.join(os.path.dirname(kokoro_onnx.__file__), 'config.json'))")

echo "📍 Kokoro config: $KOKORO_CONFIG"
echo "📍 Espeak data:   $ESPEAK_PATH"

# 3. COMPILE (Kokoro-only — ~300 MB vs ~700 MB with Kitten)
$PYTHON_EXEC -m PyInstaller --clean --noconsole --onedir --noconfirm --name 'SuperSayServer' \
    --paths . \
    --add-data 'kokoro-v1.0.onnx:.' \
    --add-data 'voices-v1.0.bin:.' \
    --add-data "$ESPEAK_PATH:espeakng_loader" \
    --collect-all 'phonemizer' \
    --collect-all 'language_tags' \
    --collect-all 'kokoro_onnx' \
    --collect-all 'misaki' \
    --collect-all 'pdfplumber' \
    --collect-all 'pdfminer' \
    --collect-all 'pypdfium2' \
    --collect-all 'pypdfium2_raw' \
    --collect-all 'google.genai' \
    --collect-all 'PIL' \
    --hidden-import 'uvicorn.loops.asyncio' \
    --hidden-import 'uvicorn.protocols.http.h11_impl' \
    --hidden-import 'fastapi' \
    --hidden-import 'starlette' \
    --hidden-import 'python_multipart' \
    --hidden-import 'multipart' \
    --hidden-import 'google.genai.types' \
    --hidden-import 'pdfminer.layout' \
    --hidden-import 'pdfminer.high_level' \
    app/main.py

# 4. SURGICAL INJECTION — force-copy config.json if collect-all missed it
DEST_DIR="dist/SuperSayServer/_internal/kokoro_onnx"
if [ ! -f "$DEST_DIR/config.json" ]; then
    echo "💉 Manual injection of config.json..."
    mkdir -p "$DEST_DIR"
    cp "$KOKORO_CONFIG" "$DEST_DIR/"
else
    echo "✅ config.json collected automatically."
fi

# 5. ZIP AND MOVE
echo "📦 Zipping backend..."
cd dist
zip -r -q SuperSayServer.zip SuperSayServer
cd ..

echo "📦 Installing to Resources..."
mkdir -p ../frontend/SuperSay/SuperSay/Resources/
mv dist/SuperSayServer.zip ../frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip

echo "✅ Backend build complete."
