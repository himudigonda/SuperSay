from typing import Optional

from app.services.audio import AudioService
from app.services.tts import TTSEngine
from fastapi import APIRouter, BackgroundTasks, Body, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

router = APIRouter()


class SpeakRequest(BaseModel):
    text: str
    voice: str = "af_bella"
    speed: float = 1.0
    volume: float = 1.0
    lang: str = "en-us"


class PrewarmRequest(BaseModel):
    text: Optional[str] = None
    voice: Optional[str] = None
    speed: Optional[float] = None


@router.get("/health")
def health_check():
    """
    Swift polls this to know when the backend is ready.

    Always returns HTTP 200 while the server process is running — even when the
    ONNX model has been idle-unloaded. Returning 503 here would cause the Swift
    heartbeat to kill and restart the entire process unnecessarily.

    The `loaded` field lets the UI distinguish "fully ready" from "cold standby"
    (model will auto-reload on the next /speak request).
    """
    loaded = TTSEngine.is_loaded()
    return {"status": "ready" if loaded else "cold", "loaded": loaded}


async def _do_prewarm(req: Optional[PrewarmRequest]) -> None:
    """Background task: ensure model is loaded, then optionally fill lookahead cache."""
    await TTSEngine.ensure_loaded()
    if req and req.text and req.voice and req.speed is not None:
        await TTSEngine.prewarm_with_lookahead(req.text, req.voice, req.speed)


@router.post("/prewarm")
async def prewarm(
    background_tasks: BackgroundTasks,
    req: Optional[PrewarmRequest] = Body(default=None),
):
    """
    Fire-and-forget warm-up: called by the Swift client when it detects a clipboard
    change or the app gains focus, before the user has pressed the hotkey.

    Returns immediately. When a JSON body with {text, voice, speed} is provided,
    the backend also pre-runs inference on the first text segment and caches the
    audio so /speak can stream it instantly (cache-hit TTFA <20ms).
    """
    background_tasks.add_task(_do_prewarm, req)
    return {"status": "warming"}


@router.post("/speak")
async def speak(req: SpeakRequest):
    try:
        # If the model was idle-unloaded, reload it now (~1.3 s warm-up).
        # This blocks the HTTP response until the model is ready, then streams
        # audio normally — the Swift "thinking" spinner covers the extra wait.
        await TTSEngine.ensure_loaded()
        TTSEngine.touch()

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
        return Response(status_code=500, content=str(e))
