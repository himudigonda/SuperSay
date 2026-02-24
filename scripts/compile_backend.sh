#!/bin/bash
set -e
echo "🚀 STARTING FINAL SURGICAL BUILD..."

# 1. Cleanup
pkill -9 SuperSayServer || true
rm -rf backend/dist backend/build
rm -f backend/SuperSayServer.spec
rm -f frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip

cd backend
uv sync

# 2. SURGICALLY LOCATE ASSETS
# This finds the actual files in your venv so we can force them into the bundle
KOKORO_DIR=$(uv run python -c "import kokoro_onnx, os; print(os.path.dirname(kokoro_onnx.__file__))")
ESPEAK_DIR=$(uv run python -c "import espeakng_loader, os; print(os.path.dirname(espeakng_loader.__file__))")

echo "📍 Found Kokoro at: $KOKORO_DIR"
echo "📍 Found Espeak at: $ESPEAK_DIR"

# 3. COMPILE
# We manually map the internal config.json into the kokoro_onnx subfolder.
# We DO NOT use --collect-all for kokoro_onnx to avoid conflicts.
uv run pyinstaller --clean --noconsole --onedir --noconfirm --name "SuperSayServer" \
    --paths . \
    --add-data "kokoro-v1.0.onnx:." \
    --add-data "voices-v1.0.bin:." \
    --add-data "$KOKORO_DIR/config.json:kokoro_onnx" \
    --add-data "$ESPEAK_DIR:espeakng_loader" \
    --collect-all "phonemizer" \
    --collect-all "language_tags" \
    --hidden-import "uvicorn.loops.asyncio" \
    --hidden-import "uvicorn.protocols.http.h11_impl" \
    --hidden-import "fastapi" \
    --hidden-import "starlette" \
    --hidden-import "kokoro_onnx" \
    app/main.py

# 4. ZIP AND MOVE
echo "📦 Zipping backend..."
cd dist
zip -r -q SuperSayServer.zip SuperSayServer
cd ..

echo "📦 Installing to Resources..."
mkdir -p ../frontend/SuperSay/SuperSay/Resources/
mv dist/SuperSayServer.zip ../frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip

echo "✅ [SUCCESS] All assets surgically bundled."
