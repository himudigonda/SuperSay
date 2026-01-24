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
# Notice we point to 'app/main.py' now.
# We also need --paths . to ensure the 'app' module is found.
uv run pyinstaller --clean --noconsole --onefile --noconfirm --name "SuperSayServer" \
    --paths . \
    --add-data "kokoro-v1.0.onnx:." \
    --add-data "voices-v1.0.bin:." \
    --add-data "$ESPEAK_PATH:espeakng_loader" \
    --collect-all "kokoro_onnx" \
    --collect-all "phonemizer" \
    --collect-all "language_tags" \
    --hidden-import "uvicorn.loops.asyncio" \
    --hidden-import "uvicorn.protocols.http.h11_impl" \
    app/main.py

# 4. MOVE BINARY
# UPDATE: Move compiled binary to the new frontend location
echo "📦 Moving binary to Xcode resources..."
mkdir -p ../frontend/SuperSay/SuperSay/Resources/
mv dist/SuperSayServer ../frontend/SuperSay/SuperSay/Resources/SuperSayServer

echo "✅ Compiled and installed to frontend/SuperSay/SuperSay/Resources/SuperSayServer"
