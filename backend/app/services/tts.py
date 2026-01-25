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
    # CHANGE: Return type is now an async generator
    async def generate(
        cls, text: str, voice: str, speed: float
    ) -> AsyncGenerator[np.ndarray, None]:
        if not cls._model:
            raise RuntimeError("Model not initialized. Call initialize() first.")

        import asyncio

        import anyio

        # 1. Clean & Split Text granularly for manual pauses
        raw_text = text.replace("\n", " ").strip()
        # Split after punctuation groups, but NOT inside them (e.g., don't split '...')
        segments = [
            s for s in re.split(r"(?<=[,.!?;:])(?![,.!?;:])\s*", raw_text) if s.strip()
        ]

        if not segments:
            segments = [raw_text]

        print(f"[TTS] 🧩 Internal splitting into {len(segments)} segments")
        for idx, seg in enumerate(segments):
            print(f'  [{idx}] "{seg}" ({len(seg)} chars)')

        pause_map = {
            ".": 0.8,
            "!": 0.8,
            "?": 0.8,
            ",": 0.4,
            ":": 0.6,
            ";": 0.6,
        }

        # 2. Advanced Parallel Inference with Sequential Yielding
        async def generate_segment(seg: str, index: int):
            try:
                print(f"[TTS] ⚡️ Starting inference for segment {index}...")
                audio, _ = await anyio.to_thread.run_sync(
                    lambda: cls._model.create(
                        seg.strip(), voice=voice, speed=speed, lang="en-us"
                    )
                )
                if audio is None:
                    print(f"[TTS] ⚠️ Segment {index} returned NULL audio")
                else:
                    print(f"[TTS] ✅ Segment {index} generated ({len(audio)} samples)")
                return audio
            except Exception as e:
                print(f"[TTS] ❌ Error generating segment {index}: {e}")
                return None

        # Fire off all inferences in parallel using REAL tasks
        tasks = [
            asyncio.create_task(generate_segment(s, i)) for i, s in enumerate(segments)
        ]

        # 3. Consumption Loop (Maintains Order)
        print("DEBUG [TTS] Starting sequential consumption of tasks...")
        for i, segment_text in enumerate(segments):
            print(f"DEBUG [TTS] Waiting for segment {i} audio...")
            audio = await tasks[i]
            print(f"DEBUG [TTS] Segment {i} received. Yielding to stream.")

            if audio is not None:
                audio = AudioService.apply_fade(audio)
                yield audio

                # Manual gaps based on punctuation type
                stripped = segment_text.rstrip()
                last_char = stripped[-1] if stripped else ""

                if stripped.endswith("..."):
                    silence_sec = 1.0
                else:
                    silence_sec = pause_map.get(last_char, 0.2)

                if silence_sec > 0:
                    yield AudioService.generate_silence(silence_sec)
