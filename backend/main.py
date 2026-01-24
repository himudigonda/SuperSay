import asyncio  # <--- CRITICAL FIX
import io
import logging  # <--- CRITICAL FIX
import os
import sys

import numpy as np
import soundfile as sf
import uvicorn.lifespan.on
import uvicorn.logging
import uvicorn.loops.asyncio

# --- CRITICAL PYINSTALLER FIXES ---
# Force uvicorn to see these modules so PyInstaller bundles them
import uvicorn.loops.auto
import uvicorn.protocols.http.auto
import uvicorn.protocols.http.h11_impl
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

# ----------------------------------


# --- Configure Espeak BEFORE importing Kokoro ---
try:
    import espeakng_loader
    import phonemizer

    # 1. Get paths
    espeak_lib_path = espeakng_loader.get_library_path()
    espeak_data_path = espeakng_loader.get_data_path()

    # 2. Force Environment Variables
    if espeak_lib_path:
        os.environ["PHONEMIZER_ESPEAK_LIBRARY"] = espeak_lib_path

    if espeak_data_path:
        os.environ["ESPEAK_DATA_PATH"] = espeak_data_path

    # 3. CRITICAL: Test if phonemizer can actually see it immediately
    # This prevents the lazy-load crash later during inference
    print(f"🔧 Espeak Lib: {espeak_lib_path}")
    print(f"🔧 Espeak Data: {espeak_data_path}")

except ImportError as e:
    print(f"⚠️ Could not setup espeakng_loader: {e}")

# Import Kokoro after env vars are set
from kokoro_onnx import Kokoro

app = FastAPI(title="SuperSay TTS Production Backend")


def get_resource_path(relative_path):
    """Get absolute path to resource, works for dev and for PyInstaller"""
    base_path = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base_path, relative_path)


# Resource Initialization
MODEL_PATH = get_resource_path("kokoro-v1.0.onnx")
VOICES_PATH = get_resource_path("voices-v1.0.bin")

# Global model variable
kokoro = None


@app.on_event("startup")
async def startup_event():
    """Load model on startup to ensure memory is ready before requests"""
    global kokoro
    try:
        print("Loading Kokoro model...")
        kokoro = Kokoro(MODEL_PATH, VOICES_PATH)
        print("✅ Model loaded successfully.")
    except Exception as e:
        print(f"CRITICAL: Failed to load model: {e}")
        # We don't exit here so the server stays alive to report the error,
        # but the app will know via health check
        pass


class TextRequest(BaseModel):
    text: str
    voice: str = "af_bella"
    speed: float = 1.0
    volume: float = 1.0
    lang: str = "en-us"


@app.get("/voices")
async def get_voices():
    return {
        "voices": [
            {"id": "af_bella", "name": "Bella", "accent": "US"},
            {"id": "af_sarah", "name": "Sarah", "accent": "US"},
            {"id": "am_adam", "name": "Adam", "accent": "US"},
            {"id": "am_michael", "name": "Michael", "accent": "US"},
            {"id": "bf_emma", "name": "Emma", "accent": "UK"},
            {"id": "bf_isabella", "name": "Isabella", "accent": "UK"},
            {"id": "bm_george", "name": "George", "accent": "UK"},
            {"id": "bm_lewis", "name": "Lewis", "accent": "UK"},
        ]
    }


@app.post("/speak")
async def speak(request: TextRequest):
    global kokoro
    if kokoro is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        # Split text by sentences
        import re

        sentences = re.split(r"(?<=[.!?])\s+", request.text.strip())
        sentences = [s.strip() for s in sentences if s.strip()]
        if not sentences:
            sentences = [request.text]

        combined_samples = []
        sample_rate = 24000

        # Process
        for sentence in sentences:
            if not sentence:
                continue

            # Ensure no async conflicts by running blocking code carefully
            samples, sr = kokoro.create(
                sentence, voice=request.voice, speed=request.speed, lang=request.lang
            )
            sample_rate = sr
            if samples is not None and len(samples) > 0:
                combined_samples.append(samples)

        if not combined_samples:
            raise HTTPException(status_code=400, detail="No audio generated")

        final_samples = np.concatenate(combined_samples)

        if request.volume > 1.0:
            final_samples = np.clip(final_samples * request.volume, -1.0, 1.0)

        buffer = io.BytesIO()
        sf.write(buffer, final_samples, sample_rate, format="WAV")
        buffer.seek(0)

        return StreamingResponse(buffer, media_type="audio/wav")

    except Exception as e:
        print(f"❌ Inference error: {e}")
        # Print full traceback to stdout for capturing
        import traceback

        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health():
    if kokoro is None:
        raise HTTPException(status_code=503, detail="Model loading failed")
    return {"status": "ok", "model": "kokoro-v1.0"}


if __name__ == "__main__":
    # CRITICAL: Force the loop policy for macOS frozen binaries
    if sys.platform == "darwin":
        try:
            asyncio.set_event_loop_policy(asyncio.DefaultEventLoopPolicy())
        except Exception:
            pass

    # Run uvicorn with explicit loop configuration
    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=8000,
        loop="asyncio",  # <--- FORCE ASYNCIO
        log_level="info",
        workers=1,
    )
