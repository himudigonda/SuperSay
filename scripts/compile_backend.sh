#!/bin/bash
set -e
echo "🚀 STARTING DEFINITIVE BUILD..."

# 1. Cleanup
pkill -9 SuperSayServer || true
rm -rf backend/dist backend/build
# UPDATE: Path moved to frontend/
rm -f frontend/SuperSay/SuperSay/Resources/SuperSayServer

cd backend
uv sync
uv pip install pyinstaller

# 2. Get Espeak
ESPEAK_PATH=$(uv run python -c "import os, espeakng_loader; print(os.path.dirname(espeakng_loader.__file__))")

# 3. COMPILE
# Use --onedir for stability
uv run pyinstaller --clean --noconsole --onedir --noconfirm --name "SuperSayServer" \
    --paths . \
    --add-data "kokoro-v1.0.onnx:." \
    --add-data "voices-v1.0.bin:." \
    --add-data "$ESPEAK_PATH:espeakng_loader" \
    --collect-all "kokoro_onnx" \
    --collect-all "phonemizer" \
    --collect-all "language_tags" \
    --hidden-import "uvicorn.loops.asyncio" \
    --hidden-import "uvicorn.protocols.http.h11_impl" \
    --hidden-import "fastapi" \
    --hidden-import "starlette" \
    app/main.py

# 4. ZIP AND MOVE
echo "📦 Zipping backend for embedding..."
cd dist
zip -r -q SuperSayServer.zip SuperSayServer
cd ..

echo "📦 Moving zip to Xcode resources..."
mkdir -p ../frontend/SuperSay/SuperSay/Resources/
rm -rf ../frontend/SuperSay/SuperSay/Resources/SuperSayServer
rm -f ../frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip
mv dist/SuperSayServer.zip ../frontend/SuperSay/SuperSay/Resources/SuperSayServer.zip

echo "✅ Backend zipped and installed to Resources/SuperSayServer.zip"
