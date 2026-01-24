import os

import uvicorn
from app.api.endpoints import router
from app.core.config import settings
from app.services.tts import TTSEngine
from fastapi import FastAPI

# Force asyncio backend for uvicorn compatibility
os.environ["ANYIO_BACKEND"] = "asyncio"

from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    TTSEngine.initialize()
    yield
    # Shutdown (if needed)


app = FastAPI(title=settings.PROJECT_NAME, version=settings.VERSION, lifespan=lifespan)


app.include_router(router)

if __name__ == "__main__":
    # This entry point is used by PyInstaller and Dev
    uvicorn.run(app, host=settings.HOST, port=settings.PORT, workers=1, loop="asyncio")
