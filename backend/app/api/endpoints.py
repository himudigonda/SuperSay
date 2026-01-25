from app.services.audio import AudioService
from app.services.tts import TTSEngine
from fastapi import APIRouter, HTTPException, Response

# NEW: Import StreamingResponse
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
        print(f"DEBUG [API] >>> New Request Received")
        print(f'DEBUG [API] Text: "{req.text}"')
        print(
            f"DEBUG [API] Voice: {req.voice}, Speed: {req.speed}, Volume: {req.volume}"
        )

        # Check if model is initialized early to catch errors before streaming
        if TTSEngine._model is None:
            raise RuntimeError("Model not initialized")

        # TTSEngine.generate is now an async generator
        raw_samples_generator = TTSEngine.generate(req.text, req.voice, req.speed)
        print(
            f'DEBUG [TTS] >>> Starting Generation for: "{req.text[:50]}..."'
        )  # Added tracing log here

        # AudioService.stream_samples_to_wav is now an async generator
        wav_chunk_generator = AudioService.stream_samples_to_wav(
            raw_samples_generator, req.volume
        )

        # Use StreamingResponse to send the audio chunks as they are generated
        return StreamingResponse(
            wav_chunk_generator,
            media_type="audio/wav",  # Client will interpret this as a stream
        )

    except Exception as e:
        print(f"[API] ❌ POST /speak Error: {e}")
        # Return HTTP 503 if the model is not ready, otherwise a generic 500
        if "Model not initialized" in str(e):
            raise HTTPException(status_code=503, detail="Initializing")
        return Response(status_code=500, content=str(e))
