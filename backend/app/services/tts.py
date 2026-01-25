import re

# NEW: Import for typing the generator
from typing import Generator

import numpy as np
from app.core.config import settings
from app.services.audio import AudioService
from kokoro_onnx import Kokoro


class TTSEngine:
    _instance = None
    _model: Kokoro = None

    @classmethod
    def initialize(cls):
        """Loads the ONNX model into memory."""
        if cls._model is None:
            print(f"[TTS] Loading model from: {settings.MODEL_PATH}")
            try:
                cls._model = Kokoro(settings.MODEL_PATH, settings.VOICES_PATH)
                print("[TTS] ✅ Model Loaded Successfully")
            except Exception as e:
                print(f"[TTS] ❌ Fatal Error: {e}")
                raise e

    @classmethod
    # CHANGE: Return type is now an async generator
    async def generate(cls, text: str, voice: str, speed: float):
        if not cls._model:
            raise RuntimeError("Model not initialized. Call initialize() first.")

        import anyio

        # 1. Clean & Split Text
        raw_text = text.replace("\n", " ").strip()
        sentences = re.split(r"(?<=[.!?])\s+", raw_text)
        sentences = [s for s in sentences if len(s.strip()) > 0]

        if not sentences:
            sentences = [raw_text]

        silence = AudioService.generate_silence(0.2)
        is_first_chunk = True

        # 2. Inference Loop: Now async
        for sentence in sentences:
            # Run blocking inference in a thread to allow other requests to proceed
            audio, _ = await anyio.to_thread.run_sync(
                lambda: cls._model.create(
                    sentence, voice=voice, speed=speed, lang="en-us"
                )
            )

            if audio is not None:
                if not is_first_chunk:
                    yield silence

                yield audio
                is_first_chunk = False
