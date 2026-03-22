"""EngineManager — single point of dispatch for TTS inference.

Holds references to both TTSEngine (Kokoro) and KittenEngine, tracks which
one is "active", and exposes a unified async generate() interface so that
endpoints don't need to know which engine is selected.
"""

from typing import AsyncGenerator, Literal

import numpy as np
from app.services.kitten_engine import KITTEN_DEFAULT_VOICE, KITTEN_VOICES, KittenEngine
from app.services.tts import TTSEngine

KOKORO_VOICES = [
    "af_bella",
    "af_sarah",
    "am_adam",
    "am_michael",
    "bf_emma",
    "bf_isabella",
    "bm_george",
    "bm_lewis",
]
KOKORO_DEFAULT_VOICE = "af_bella"

EngineID = Literal["kokoro", "kitten"]


class EngineManager:
    active: EngineID = "kokoro"
    _model_name: str = ""  # tracks current kitten model variant

    @classmethod
    def voices(cls) -> list[str]:
        return KOKORO_VOICES if cls.active == "kokoro" else KITTEN_VOICES

    @classmethod
    def default_voice(cls) -> str:
        return KOKORO_DEFAULT_VOICE if cls.active == "kokoro" else KITTEN_DEFAULT_VOICE

    @classmethod
    def state(cls) -> dict:
        return {
            "engine": cls.active,
            "model": cls._model_name,
            "voices": cls.voices(),
        }

    @classmethod
    async def switch(cls, engine: EngineID, model: str | None = None) -> None:
        """Switch the active engine. Unloads old engine, ensures new one is loaded."""
        if engine == cls.active and model in (None, cls._model_name):
            return

        # Unload old engine
        if cls.active == "kokoro":
            TTSEngine.unload()
        else:
            KittenEngine.unload()

        cls.active = engine
        if model:
            cls._model_name = model

        # Load new engine — pass variant to KittenEngine
        if engine == "kokoro":
            await TTSEngine.ensure_loaded()
        else:
            variant = cls._model_name or "nano"
            await KittenEngine.ensure_loaded(variant)

    @classmethod
    async def ensure_loaded(cls) -> None:
        if cls.active == "kokoro":
            await TTSEngine.ensure_loaded()
        else:
            variant = cls._model_name or "nano"
            await KittenEngine.ensure_loaded(variant)

    @classmethod
    def touch(cls) -> None:
        if cls.active == "kokoro":
            TTSEngine.touch()
        else:
            KittenEngine.touch()

    @classmethod
    async def generate(
        cls, text: str, voice: str, speed: float
    ) -> AsyncGenerator[np.ndarray, None]:
        """Dispatch to active engine and yield audio chunks."""
        if cls.active == "kokoro":
            async for chunk in TTSEngine.generate(text, voice, speed):
                yield chunk
        else:
            async for chunk in KittenEngine.generate(text, voice, speed):
                yield chunk

    @classmethod
    async def prewarm_with_lookahead(cls, text: str, voice: str, speed: float) -> None:
        if cls.active == "kokoro":
            await TTSEngine.prewarm_with_lookahead(text, voice, speed)
        # KittenEngine does not implement lookahead cache (can be added later)

    @classmethod
    def is_loaded(cls) -> bool:
        """Return True if the currently active engine's model is in memory."""
        if cls.active == "kokoro":
            return TTSEngine.is_loaded()
        return KittenEngine.is_loaded()

    @classmethod
    def initialize(cls) -> None:
        """Initialize the default engine (Kokoro) at startup."""
        TTSEngine.initialize()
        cls._model_name = ""
