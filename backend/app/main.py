import asyncio
import os

import uvicorn
from app.api.endpoints import router
from app.core.config import settings
from app.services.engine_manager import EngineManager
from app.services.tts import TTSEngine
from fastapi import FastAPI

# Force asyncio backend for uvicorn compatibility
os.environ["ANYIO_BACKEND"] = "asyncio"

from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize default engine (Kokoro), launch idle watchers.
    EngineManager.initialize()
    asyncio.create_task(TTSEngine.idle_watcher())
    from app.services.kitten_engine import KittenEngine

    asyncio.create_task(KittenEngine.idle_watcher())

    # Audiobook orchestrator + crash-recovery
    from app.services.audiobook_service import AudiobookService

    AudiobookService.initialize()
    asyncio.create_task(AudiobookService.resume_in_progress())

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
