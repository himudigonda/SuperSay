from app.services.audio import AudioService
from app.services.tts import TTSEngine
from fastapi import APIRouter, HTTPException, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

router = APIRouter()


class SpeakRequest(BaseModel):
    text: str
    voice: str = "af_bella"
    speed: float = 1.0
    volume: float = 1.0
    lang: str = "en-us"


@router.get("/health")
def health_check():
    """
    Swift polls this to know when the backend is ready.
    """
    if TTSEngine._model is None:
        raise HTTPException(status_code=503, detail="Initializing")
    return {"status": "ok", "model": "loaded"}


@router.post("/speak")
async def speak(req: SpeakRequest):
    try:
        if TTSEngine._model is None:
            raise RuntimeError("Model not initialized")

        raw_samples_generator = TTSEngine.generate(req.text, req.voice, req.speed)
        wav_chunk_generator = AudioService.stream_samples_to_wav(
            raw_samples_generator, req.volume
        )

        return StreamingResponse(
            wav_chunk_generator,
            media_type="audio/wav",
        )

    except Exception as e:
        print(f"[API] ❌ POST /speak Error: {e}")
        if "Model not initialized" in str(e):
            raise HTTPException(status_code=503, detail="Initializing")
        return Response(status_code=500, content=str(e))
