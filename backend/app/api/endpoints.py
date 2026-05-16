import asyncio
import json
import os
from typing import Any, Optional

from app.services.audio import AudioService
from app.services.audiobook_service import AudiobookService
from app.services.audiobook_store import AudiobookStore
from app.services.engine_manager import EngineManager
from app.services.gemini_cleaner import GeminiCleaner
from app.services.pdf_extractor import PDFExtractor
from app.services.tts import interactive_tts_lock
from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    File,
    Form,
    Header,
    HTTPException,
    Response,
    UploadFile,
)
from fastapi.responses import FileResponse, StreamingResponse
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


class EngineRequest(BaseModel):
    engine: str
    model: Optional[str] = None


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
    loaded = EngineManager.is_loaded()
    return {"status": "ready" if loaded else "cold", "loaded": loaded}


@router.get("/engine")
def get_engine():
    """Return current active engine, model, and available voices."""
    return EngineManager.state()


@router.post("/engine")
async def set_engine(req: EngineRequest):
    """Switch active TTS engine at runtime. No restart required."""
    if req.engine not in ("kokoro", "kitten"):
        return Response(status_code=400, content=f"Unknown engine: {req.engine}")
    await EngineManager.switch(req.engine, req.model)  # type: ignore[arg-type]
    return EngineManager.state()


async def _do_prewarm(req: Optional[PrewarmRequest]) -> None:
    """Background task: ensure model is loaded, then optionally fill lookahead cache."""
    await EngineManager.ensure_loaded()
    if req and req.text and req.voice and req.speed is not None:
        await EngineManager.prewarm_with_lookahead(req.text, req.voice, req.speed)


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


async def _guarded_wav_stream(wav_generator, lock_holder=None):
    """Wrap WAV streaming with error handling and release the preemption lock
    when the stream finishes (so audiobook generation can resume)."""
    try:
        async for chunk in wav_generator:
            yield chunk
    except Exception as e:
        print(f"[API] ❌ Error during /speak streaming: {e}")
    finally:
        if lock_holder is not None and lock_holder.locked():
            lock_holder.release()


@router.post("/speak")
async def speak(req: SpeakRequest):
    try:
        # Acquire preemption lock so any in-flight audiobook TTS phase pauses
        # at its next inter-page checkpoint until this stream finishes.
        await interactive_tts_lock.acquire()

        # If the model was idle-unloaded, reload it now (~1.3 s warm-up).
        await EngineManager.ensure_loaded()
        EngineManager.touch()

        raw_samples_generator = EngineManager.generate(req.text, req.voice, req.speed)
        wav_chunk_generator = AudioService.stream_samples_to_wav(
            raw_samples_generator, req.volume
        )
        guarded_stream = _guarded_wav_stream(
            wav_chunk_generator, lock_holder=interactive_tts_lock
        )

        return StreamingResponse(
            guarded_stream,
            media_type="audio/wav",
        )

    except Exception as e:
        # If we acquired the lock but bombed before returning the stream, release.
        if interactive_tts_lock.locked():
            interactive_tts_lock.release()
        print(f"[API] ❌ POST /speak Error: {e}")
        return Response(status_code=500, content=str(e))


# ============================================================================
# Audiobook endpoints
# ============================================================================


class AudiobookEstimate(BaseModel):
    book_id: str
    title: str
    page_count: int
    word_count_estimate: int
    estimated_processing_seconds: float
    estimated_audio_seconds: float
    estimated_cost_usd: float
    estimated_token_count: int
    is_image_only: bool
    cost_warning: bool


class VerifyKeyRequest(BaseModel):
    api_key: str


# Configurable cost-cap threshold; warn (don't block) above this estimated USD.
COST_WARNING_THRESHOLD_USD = 1.00


@router.post("/audiobook", response_model=AudiobookEstimate)
async def upload_audiobook(
    file: UploadFile = File(...),
    voice: Optional[str] = Form(default=None),
    speed: Optional[float] = Form(default=None),
    engine: Optional[str] = Form(default=None),
):
    """Save the uploaded PDF, extract estimate, return book_id + stats. No processing yet.

    Optional `voice`, `speed`, `engine` form fields snapshot the user's current
    selection for this book. If omitted, falls back to the engine's default.
    """
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF files are supported.")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="The uploaded PDF is empty.")
    if len(content) < 100:
        # A real PDF starts with '%PDF-' and has at least a header + xref.
        raise HTTPException(
            status_code=400, detail="The uploaded file is too small to be a valid PDF."
        )
    title = file.filename or "Untitled.pdf"

    book_id = AudiobookStore.create_book(title)
    AudiobookStore.save_pdf(book_id, content)

    pdf_path = AudiobookStore.pdf_path(book_id)
    loop = asyncio.get_running_loop()

    try:
        page_count = await loop.run_in_executor(None, PDFExtractor.page_count, pdf_path)
        is_image_only = await loop.run_in_executor(
            None, PDFExtractor.is_image_only, pdf_path
        )
    except Exception as e:
        AudiobookStore.delete_book(book_id)
        raise HTTPException(status_code=400, detail=f"Could not read PDF: {e}") from e

    # P9: reject zero-page PDFs early — the pipeline would "complete" instantly
    # with no audio, leaving the user confused. Delete the staged book before
    # returning the error so it doesn't appear in the library.
    if page_count == 0:
        AudiobookStore.delete_book(book_id)
        raise HTTPException(
            status_code=400,
            detail="This PDF has no extractable pages. Try a different file.",
        )

    # Image-only books are processed via Gemini vision OCR — no rejection.
    # Substitute a per-page character estimate for the cost/duration calculation
    # since text extraction returns nothing useful for scanned pages.
    _OCR_CHARS_PER_PAGE = 1500  # ~250 words × 6 chars/word
    if is_image_only:
        sample_words = 250
        sample_chars = _OCR_CHARS_PER_PAGE
    else:
        sample_words = await loop.run_in_executor(
            None, PDFExtractor.sample_word_count, pdf_path
        )
        sample_chars = await loop.run_in_executor(
            None, PDFExtractor.sample_char_count, pdf_path
        )

    # Render cover in background — UI fetches /audiobook/{id}/cover when ready.
    # P2: write cover_status to meta so the UI knows whether to keep retrying
    # (/cover returns 404 until ready; "failed" means stop retrying).
    async def _bg_render_cover() -> None:
        try:
            await loop.run_in_executor(None, PDFExtractor.render_cover, book_id)
            await AudiobookStore.update_meta(book_id, cover_status="ready")
        except Exception as e:
            print(f"[API] cover render failed for {book_id}: {e}")
            await AudiobookStore.update_meta(book_id, cover_status="failed")

    asyncio.create_task(_bg_render_cover())

    book_speed = float(speed) if speed is not None else 1.0
    estimate = AudiobookService.estimate(
        page_count=page_count,
        sample_words=sample_words,
        sample_chars=sample_chars,
        speed=book_speed,
    )
    estimate["token_count"] = GeminiCleaner.estimate_tokens(sample_chars * page_count)

    state = EngineManager.state()
    book_engine = engine or state.get("engine", "kokoro")
    default_voice = (
        state.get("voices", ["af_bella"])[0] if state.get("voices") else "af_bella"
    )
    book_voice = voice or default_voice

    meta = AudiobookStore.initial_meta(
        book_id=book_id,
        title=title,
        page_count=page_count,
        engine=book_engine,
        voice=book_voice,
        speed=book_speed,
        estimated=estimate,
    )
    AudiobookStore.write_meta(book_id, meta)

    return AudiobookEstimate(
        book_id=book_id,
        title=title,
        page_count=page_count,
        estimated_token_count=estimate["token_count"],
        cost_warning=estimate["cost_usd"] >= COST_WARNING_THRESHOLD_USD,
        word_count_estimate=estimate["words"],
        estimated_processing_seconds=estimate["processing_seconds"],
        estimated_audio_seconds=estimate["audio_seconds"],
        estimated_cost_usd=estimate["cost_usd"],
        is_image_only=is_image_only,
    )


@router.post("/audiobook/{book_id}/start")
async def start_audiobook(
    book_id: str,
    x_gemini_api_key: Optional[str] = Header(default=None, alias="X-Gemini-Api-Key"),
):
    if not x_gemini_api_key:
        raise HTTPException(status_code=400, detail="Missing X-Gemini-Api-Key header.")
    if AudiobookStore.read_meta(book_id) is None:
        raise HTTPException(status_code=404, detail="Book not found.")
    await AudiobookService.enqueue(book_id, x_gemini_api_key)
    return {"status": "queued", "book_id": book_id}


@router.get("/audiobook/{book_id}/events")
async def audiobook_events(book_id: str):
    if AudiobookStore.read_meta(book_id) is None:
        raise HTTPException(status_code=404, detail="Book not found.")

    async def stream():
        q = AudiobookService.subscribe(book_id)
        try:
            # Emit current status immediately so the client doesn't need to poll first.
            meta = AudiobookStore.read_meta(book_id) or {}
            yield f"data: {json.dumps({'type': 'snapshot', **meta})}\n\n"
            while True:
                try:
                    event = await asyncio.wait_for(q.get(), timeout=15.0)
                except asyncio.TimeoutError:
                    yield ": keep-alive\n\n"
                    continue
                yield f"data: {json.dumps(event)}\n\n"
                if event.get("type") in {"done", "failed"}:
                    break
        finally:
            AudiobookService.unsubscribe(book_id, q)

    return StreamingResponse(stream(), media_type="text/event-stream")


@router.get("/audiobook")
def list_audiobooks() -> list[dict[str, Any]]:
    return AudiobookStore.list_books()


@router.get("/audiobook/{book_id}")
def get_audiobook(book_id: str):
    meta = AudiobookStore.read_meta(book_id)
    if meta is None:
        raise HTTPException(status_code=404, detail="Book not found.")
    return meta


@router.get("/audiobook/{book_id}/audio")
def get_audiobook_audio(
    book_id: str,
    range_header: Optional[str] = Header(default=None, alias="Range"),
):
    """Stream audio.wav with HTTP Range support for AVAudioPlayer seeking."""
    path = AudiobookStore.audio_path(book_id)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Audio not ready.")

    file_size = os.path.getsize(path)
    if not range_header:
        return FileResponse(
            path,
            media_type="audio/wav",
            filename=f"{book_id}.wav",
            headers={"Accept-Ranges": "bytes", "Content-Length": str(file_size)},
        )

    # Parse `Range: bytes=START-END` (END optional).
    try:
        units, _, rng = range_header.partition("=")
        if units.strip().lower() != "bytes":
            raise ValueError
        start_s, _, end_s = rng.partition("-")
        start = int(start_s) if start_s else 0
        end = int(end_s) if end_s else file_size - 1
        if start < 0 or end >= file_size or start > end:
            raise ValueError
    except ValueError:
        return Response(
            status_code=416, headers={"Content-Range": f"bytes */{file_size}"}
        )

    chunk_size = 1 << 16  # 64 KB per yield

    def iter_range():
        with open(path, "rb") as f:
            f.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                buf = f.read(min(chunk_size, remaining))
                if not buf:
                    break
                remaining -= len(buf)
                yield buf

    return StreamingResponse(
        iter_range(),
        status_code=206,
        media_type="audio/wav",
        headers={
            "Accept-Ranges": "bytes",
            "Content-Range": f"bytes {start}-{end}/{file_size}",
            "Content-Length": str(end - start + 1),
        },
    )


@router.get("/audiobook/{book_id}/transcript")
def get_audiobook_transcript(book_id: str):
    """Return the per-page transcript + section timing map (for live highlighting)."""
    path = AudiobookStore.transcript_path(book_id)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Transcript not ready.")
    return FileResponse(path, media_type="application/json")


@router.post("/audiobook/{book_id}/cancel")
def cancel_audiobook(book_id: str):
    if AudiobookStore.read_meta(book_id) is None:
        raise HTTPException(status_code=404, detail="Book not found.")
    AudiobookService.cancel(book_id)
    return {"status": "cancelling", "book_id": book_id}


@router.post("/audiobook/{book_id}/retry")
async def retry_audiobook(
    book_id: str,
    x_gemini_api_key: Optional[str] = Header(default=None, alias="X-Gemini-Api-Key"),
):
    """Re-process failed pages (or the whole book if state is `failed`)."""
    if AudiobookStore.read_meta(book_id) is None:
        raise HTTPException(status_code=404, detail="Book not found.")
    if not x_gemini_api_key:
        raise HTTPException(status_code=400, detail="Missing X-Gemini-Api-Key header.")
    count = await AudiobookService.retry_failed(book_id, x_gemini_api_key)
    return {"status": "queued", "retried_pages": count, "book_id": book_id}


@router.get("/audiobook/{book_id}/cover")
def get_audiobook_cover(book_id: str):
    path = AudiobookStore.cover_path(book_id)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="Cover not yet rendered.")
    return FileResponse(path, media_type="image/jpeg")


@router.delete("/audiobook/{book_id}")
async def delete_audiobook(book_id: str):
    """Coordinated delete: cancels any in-flight pipeline at its next page
    boundary, then removes the book directory. Prevents the rmtree-mid-write
    crash (C8)."""
    ok = await AudiobookService.request_delete(book_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Book not found.")
    return {"status": "deleted", "book_id": book_id}


@router.post("/audiobook/verify_key")
async def verify_key(req: VerifyKeyRequest):
    """Lightweight Gemini key verification (called from PreferencesView)."""
    ok = await GeminiCleaner.verify_key(req.api_key)
    return {"verified": ok}
