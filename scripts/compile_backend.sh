#!/bin/bash
set -e
echo "🚀 STARTING DEFINITIVE BUILD..."

# 1. Cleanup
pkill -9 SuperSayServer || true
rm -rf backend/dist backend/build
rm -f SuperSay/SuperSay/Resources/SuperSayServer

cd backend
uv sync
uv pip install pyinstaller

# 2. Get Espeak
ESPEAK_PATH=$(uv run python -c "import os, espeakng_loader; print(os.path.dirname(espeakng_loader.__file__))")

# 3. COMPILE (Bundling everything with sledgehammer)
uv run pyinstaller --clean --noconsole --onefile --noconfirm --name "SuperSayServer" \
    --add-data "kokoro-v1.0.onnx:." \
    --add-data "voices-v1.0.bin:." \
    --add-data "$ESPEAK_PATH:espeakng_loader" \
    --collect-all "kokoro_onnx" \
    --collect-all "phonemizer" \
    --collect-all "language_tags" \
    --hidden-import "uvicorn.loops.asyncio" \
    --hidden-import "uvicorn.protocols.http.h11_impl" \
    main.py

echo "✅ Compiled to backend/dist/SuperSayServer"
