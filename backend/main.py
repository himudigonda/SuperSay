import os
import sys

# --- 1. BOOTSTRAP ENVIRONMENT ---
os.environ["ANYIO_BACKEND"] = "asyncio"

import asyncio
import io
import re
import wave

import numpy as np
import uvicorn
from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel

# --- 2. ESPEAK CONFIG ---
try:
    import espeakng_loader

    os.environ["PHONEMIZER_ESPEAK_LIBRARY"] = espeakng_loader.get_library_path()
    os.environ["ESPEAK_DATA_PATH"] = espeakng_loader.get_data_path()
except:
    pass

from kokoro_onnx import Kokoro


# --- 3. PATH LOGIC ---
def get_path(rel):
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, rel)


app = FastAPI()
kokoro = None


@app.on_event("startup")
async def startup():
    global kokoro
    print("[PYTHON] --- BACKEND STARTING ---")
    try:
        kokoro = Kokoro(get_path("kokoro-v1.0.onnx"), get_path("voices-v1.0.bin"))
        print("[PYTHON] ✅ Model Ready")
    except Exception as e:
        print(f"[PYTHON] ❌ Load Failed: {e}")


class Req(BaseModel):
    text: str
    voice: str = "af_bella"
    speed: float = 1.0


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/speak")
async def speak(req: Req):
    if not kokoro:
        raise HTTPException(status_code=500)

    try:
        # Split text into sentences for stability
        text = req.text.replace("\n", " ").strip()
        sentences = re.split(r"(?<=[.!?])\s+", text)
        sentences = [s for s in sentences if s.strip()]

        if not sentences:
            sentences = [text]

        combined_audio = []
        for s in sentences:
            audio, _ = kokoro.create(s, voice=req.voice, speed=req.speed, lang="en-us")
            if audio is not None:
                combined_audio.append(audio)

        if not combined_audio:
            return Response(status_code=400, content="No audio")

        # Merge and convert to 16-bit PCM
        final_samples = np.concatenate(combined_audio)
        final_samples = (final_samples * 32767).astype(np.int16)

        # Write perfect RIFF WAV header
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(24000)
            wav_file.writeframes(final_samples.tobytes())

        print(f"[PYTHON] 📤 Sent {len(final_samples)} samples")
        return Response(content=buffer.getvalue(), media_type="audio/wav")

    except Exception as e:
        print(f"[PYTHON] ❌ Error: {e}")
        return Response(status_code=500, content=str(e))


if __name__ == "__main__":
    if sys.platform == "darwin":
        try:
            asyncio.set_event_loop_policy(asyncio.DefaultEventLoopPolicy())
        except:
            pass
    uvicorn.run(app, host="127.0.0.1", port=8000, workers=1, loop="asyncio")
