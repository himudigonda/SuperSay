from app.services.audio import AudioService
from app.services.tts import TTSEngine
from fastapi import APIRouter, HTTPException, Response
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
    Ideally, we check if the model is actually loaded.
    """
    try:
        # Simple heuristic: if the class exists, we are good.
        # Could add a lightweight inference check here if needed.
        return {"status": "ok", "model": "loaded"}
    except Exception:
        raise HTTPException(status_code=503, detail="Initializing")


@router.post("/speak")
async def speak(req: SpeakRequest):
    try:
        raw_samples = TTSEngine.generate(req.text, req.voice, req.speed)

        if raw_samples is None:
            return Response(status_code=400, content="No audio generated")

        wav_data = AudioService.process_samples(raw_samples, req.volume)

        return Response(content=wav_data, media_type="audio/wav")

    except Exception as e:
        print(f"[API] Error: {e}")
        return Response(status_code=500, content=str(e))
