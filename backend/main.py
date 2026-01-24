import asyncio
import io
import os
import re
import sys
import wave

import numpy as np
import uvicorn
from fastapi import FastAPI, HTTPException, Response
from kokoro_onnx import Kokoro
from pydantic import BaseModel

os.environ["ANYIO_BACKEND"] = "asyncio"


def get_path(rel):
    if getattr(sys, "frozen", False):
        base = sys._MEIPASS
    else:
        base = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base, rel)


app = FastAPI()
kokoro = None


@app.on_event("startup")
async def startup():
    global kokoro
    try:
        kokoro = Kokoro(get_path("kokoro-v1.0.onnx"), get_path("voices-v1.0.bin"))
        print("[PYTHON) ✅ Model Ready")
    except Exception as e:
        print(f"[PYTHON] ❌ Load Failed: {e}")


class Req(BaseModel):
    text: str
    voice: str = "af_bella"
    speed: float = 1.0
    volume: float = 1.0  # Added volume back


@app.post("/speak")
async def speak(req: Req):
    if not kokoro:
        raise HTTPException(status_code=500)
    try:
        # 1. SPLIT BY PUNCTUATION (The Merge Logic)
        raw_text = req.text.replace("\n", " ").strip()
        sentences = re.split(r"(?<=[.!?])\s+", raw_text)
        sentences = [s for s in sentences if len(s.strip()) > 0]

        if not sentences:
            sentences = [raw_text]

        combined_audio = []
        # 12,000 samples = 0.5s at 24,000Hz
        silence = np.zeros(12000, dtype=np.float32)

        for i, s in enumerate(sentences):
            # Kokoro has a limit of ~500 tokens. Chunking protects us.
            audio, _ = kokoro.create(s, voice=req.voice, speed=req.speed, lang="en-us")
            if audio is not None:
                if i > 0:
                    combined_audio.append(silence)
                combined_audio.append(audio)

        if not combined_audio:
            return Response(status_code=400, content="Silence generated")

        # 2. CONCATENATE ALL SENTENCES
        final_samples = np.concatenate(combined_audio)

        # 3. APPLY DIGITAL BOOST (If volume > 1.0)
        if req.volume > 1.0:
            final_samples = np.clip(final_samples * req.volume, -1.0, 1.0)

        # 4. CONVERT TO 16-BIT PCM
        final_samples = (final_samples * 32767).astype(np.int16)

        # 5. WRITE BULLETPROOF WAV HEADER
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav_file:
            wav_file.setnchannels(1)  # Mono
            wav_file.setsampwidth(2)  # 2 bytes = 16-bit
            wav_file.setframerate(24000)
            wav_file.writeframes(final_samples.tobytes())

        return Response(content=buffer.getvalue(), media_type="audio/wav")
    except Exception as e:
        print(f"[PYTHON] ❌ Error: {e}")
        return Response(status_code=500, content=str(e))


@app.get("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000, workers=1, loop="asyncio")
