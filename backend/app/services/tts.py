import re

# NEW: Import for typing the generator
from typing import AsyncGenerator, Generator

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
    async def generate(
        cls, text: str, voice: str, speed: float
    ) -> AsyncGenerator[np.ndarray, None]:
        if not cls._model:
            raise RuntimeError("Model not initialized. Call initialize() first.")

        import asyncio

        import anyio

        # 1. Clean & Split Text
        raw_text = text.replace("\n", " ").strip()
        segments = [
            s for s in re.split(r"(?<=[,.!?;:])(?![,.!?;:])\s*", raw_text) if s.strip()
        ]
        if not segments:
            segments = [raw_text]

        pause_map = {".": 0.8, "!": 0.8, "?": 0.8, ",": 0.4, ":": 0.6, ";": 0.6}

        async def generate_segment(seg: str, index: int):
            try:
                # Fire the heavy ONNX work into a thread to keep the loop free
                audio, _ = await anyio.to_thread.run_sync(
                    lambda: cls._model.create(
                        seg.strip(), voice=voice, speed=speed, lang="en-us"
                    )
                )
                return audio
            except Exception as e:
                print(f"[TTS] ❌ Error in segment {index}: {e}")
                return None

        # --- FIX: FIRE ALL TASKS IN PARALLEL ---
        tasks = [
            asyncio.create_task(generate_segment(s, i)) for i, s in enumerate(segments)
        ]

        # 2. Yield results in order as they complete
        for i, seg in enumerate(segments):
            audio = await tasks[i]  # Wait for this specific segment
            if audio is not None:
                audio = AudioService.apply_fade(audio)
                yield audio

                # Manual gaps
                stripped = seg.strip()
                last_char = stripped[-1] if stripped else ""
                silence_sec = (
                    1.0 if stripped.endswith("...") else pause_map.get(last_char, 0.2)
                )

                if silence_sec > 0:
                    yield AudioService.generate_silence(silence_sec)
