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

        # 1. Improved Splitting: Split on . ! ? : ; but group tiny fragments
        raw_text = text.replace("\n", " ").strip()
        # Splits on terminal punctuation followed by a space
        raw_segments = [
            s.strip() for s in re.split(r"(?<=[.!?|:;]) +", raw_text) if s.strip()
        ]

        segments = []
        temp_seg = ""
        for s in raw_segments:
            temp_seg += (" " + s) if temp_seg else s
            # Only finalize segment if it has enough words or a terminal mark
            if len(temp_seg.split()) > 3 or any(temp_seg.endswith(p) for p in ".!?"):
                segments.append(temp_seg.strip())
                temp_seg = ""
        if temp_seg:
            segments.append(temp_seg.strip())

        pause_map = {".": 0.6, "!": 0.6, "?": 0.7, ":": 0.4, ";": 0.4, ",": 0.2}

        async def generate_segment(seg: str):
            try:
                # Fire the heavy ONNX work into a thread to keep the loop free
                audio, _ = await anyio.to_thread.run_sync(
                    lambda: cls._model.create(
                        seg.strip(), voice=voice, speed=speed, lang="en-us"
                    )
                )
                return audio
            except Exception as e:
                print(f"[TTS] ❌ Model Error on '{seg[:20]}': {e}")
                return None

        # Fire all tasks in parallel
        tasks = [asyncio.create_task(generate_segment(s)) for s in segments]

        # 2. Yield results in order as they complete
        for i, seg in enumerate(segments):
            audio = await tasks[i]  # Wait for this specific segment
            if audio is not None:
                # Apply fade to prevent popping
                audio = AudioService.apply_fade(audio)

                # Determine silence duration
                last_char = seg.strip()[-1] if seg.strip() else ""
                silence_sec = pause_map.get(last_char, 0.2)
                silence = AudioService.generate_silence(silence_sec)

                # --- FIX: Concatenate into ONE block before yielding ---
                # This prevents the frontend from getting tiny "silence-only" chunks
                combined = np.concatenate([audio, silence])
                yield combined
