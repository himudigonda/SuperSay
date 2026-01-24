import io
import os
import sys

import numpy as np
import soundfile as sf
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

# --- Configure Espeak BEFORE importing Kokoro ---
try:
    import espeakng_loader
    import phonemizer

    # Force phonemizer to use the bundled library
    # This is critical for the PyInstaller bundle to work without system espeak
    espeak_lib_path = espeakng_loader.get_library_path()
    espeak_data_path = espeakng_loader.get_data_path()

    if espeak_lib_path:
        os.environ["PHONEMIZER_ESPEAK_LIBRARY"] = espeak_lib_path
        print(f"🔧 Configured espeak library at: {espeak_lib_path}")

    if espeak_data_path:
        os.environ["ESPEAK_DATA_PATH"] = espeak_data_path
        print(f"🔧 Configured espeak data at: {espeak_data_path}")

    if not espeak_lib_path or not espeak_data_path:
        print("⚠️ espeakng_loader found but missing paths")

except ImportError as e:
    print(f"⚠️ Could not setup espeakng_loader: {e}")

from kokoro_onnx import Kokoro

app = FastAPI(title="SuperSay TTS Production Backend")


def get_resource_path(relative_path):
    base_path = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base_path, relative_path)


# Resource Initialization
MODEL_PATH = get_resource_path("kokoro-v1.0.onnx")
VOICES_PATH = get_resource_path("voices-v1.0.bin")

try:
    print("Loading Kokoro model...")
    kokoro = Kokoro(MODEL_PATH, VOICES_PATH)
    print("Model loaded successfully.")
except Exception as e:
    print(f"CRITICAL: Failed to load model: {e}")
    sys.exit(1)


class TextRequest(BaseModel):
    text: str
    voice: str = "af_bella"
    speed: float = 1.0
    volume: float = 1.0
    lang: str = "en-us"


@app.get("/voices")
async def get_voices():
    """Returns available voice IDs"""
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
    try:
        # Split text by sentences - Python handles all chunking now
        import re

        sentences = re.split(r"(?<=[.!?])\s+", request.text.strip())
        sentences = [s.strip() for s in sentences if s.strip()]
        if not sentences:
            sentences = [request.text]

        combined_samples = []
        sample_rate = 24000

        for sentence in sentences:
            if not sentence:
                continue
            samples, sr = kokoro.create(
                sentence, voice=request.voice, speed=request.speed, lang=request.lang
            )
            sample_rate = sr
            if samples is not None and len(samples) > 0:
                combined_samples.append(samples)

        if not combined_samples:
            raise HTTPException(status_code=400, detail="No audio generated")

        # Merge all chunks into one array
        final_samples = np.concatenate(combined_samples)

        # Apply Volume Gain only if > 1.0 (Digital Boost)
        # Otherwise, Swift layer handles volume for better bit-depth
        if request.volume > 1.0:
            final_samples = np.clip(final_samples * request.volume, -1.0, 1.0)

        buffer = io.BytesIO()
        sf.write(buffer, final_samples, sample_rate, format="WAV")
        buffer.seek(0)

        print(
            f"✅ Generated {len(final_samples)} samples from {len(sentences)} sentences"
        )
        return StreamingResponse(buffer, media_type="audio/wav")
    except Exception as e:
        print(f"❌ Inference error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health():
    return {"status": "ok", "model": "kokoro-v1.0"}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
