import asyncio
import os
from contextlib import asynccontextmanager

import uvicorn
from app.api.endpoints import router
from app.core.config import settings
from app.services.engine_manager import EngineManager
from app.services.tts import TTSEngine
from fastapi import FastAPI

# Force asyncio backend for uvicorn compatibility
os.environ["ANYIO_BACKEND"] = "asyncio"

# PID of the Swift app that spawned us (captured at import time, before any fork).
_PARENT_PID = os.getppid()


async def _parent_watchdog() -> None:
    """Exit if the parent macOS app process disappears (crash, force-kill, etc.).

    Checks every 3 seconds whether the parent PID still exists via signal 0.
    When it's gone, calls os._exit(0) — a hard exit that bypasses Python
    shutdown hooks and ensures no zombie server lingers after an app crash.
    """
    while True:
        await asyncio.sleep(3)
        try:
            os.kill(_PARENT_PID, 0)  # 0 = existence check only, no signal sent
        except ProcessLookupError:
            print("[Watchdog] Parent app gone — server exiting.")
            os._exit(0)
        except PermissionError:
            pass  # process exists but we lack permission to signal it — keep running


async def _load_engine_background() -> None:
    """Load Kokoro off the event loop so uvicorn starts immediately.

    /health returns {"status": "cold", "loaded": false} until this finishes.
    /speak calls EngineManager.ensure_loaded() which waits transparently.
    Idle-watcher task is started only after the model is in memory.
    """
    loop = asyncio.get_running_loop()
    try:
        print("[Startup] Loading Kokoro TTS engine in background…")
        await loop.run_in_executor(None, EngineManager.initialize)
        print("[Startup] ✅ Kokoro TTS engine ready")
    except Exception as exc:
        print(f"[Startup] ❌ Engine init failed: {exc}")
        return

    # Wire idle-unload watcher only after the model is in RAM.
    asyncio.create_task(TTSEngine.idle_watcher())


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Kick off model load as a background task — uvicorn starts serving
    # immediately and /health returns "cold" until loading finishes (~2-3 s).
    asyncio.create_task(_load_engine_background())

    # Audiobook orchestrator + crash-recovery (fast, no I/O blocking)
    from app.services.audiobook_service import AudiobookService

    AudiobookService.initialize()
    asyncio.create_task(AudiobookService.resume_in_progress())

    # Lifecycle watchdog: exit when the parent Swift app process disappears.
    # Runs even when launched from a terminal (harmless — exits when the shell dies).
    asyncio.create_task(_parent_watchdog())

    yield
    # Shutdown (if needed)


app = FastAPI(title=settings.PROJECT_NAME, version=settings.VERSION, lifespan=lifespan)


app.include_router(router)

if __name__ == "__main__":
    # This entry point is used by PyInstaller and Dev
    # log_config=None prevents uvicorn from overriding logging, access_log=False hides the health spam
    uvicorn.run(
        app,
        host=settings.HOST,
        port=settings.PORT,
        workers=1,
        loop="asyncio",
        log_config=None,
        access_log=False,
    )
