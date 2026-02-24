import re

# NEW: Import for typing the generator
from typing import AsyncGenerator

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

        # Concurrency control: limit to 1 simultaneous ONNX thread to prevent espeak-ng global state corruption
        semaphore = asyncio.Semaphore(1)

        async def generate_segment(seg: str):
            async with semaphore:
                try:
                    # Switch to native asyncio.to_thread (standard in Python 3.11+)
                    # Note: We pass arguments directly instead of using a lambda to avoid capture group memory issues
                    audio, _ = await asyncio.to_thread(
                        cls._model.create,
                        seg.strip(),
                        voice=voice,
                        speed=speed,
                        lang="en-us",
                    )
                    return audio
                except Exception as e:
                    print(f"[TTS] ❌ Model Error on '{seg[:20]}': {e}")
                    return None

        if not segments:
            return

        # --- OPTIMIZATION: PRIORITY QUEUEING ---
        # 1. Generate the first segment immediately to minimize TTFA
        # This ensures the hardware (ANE/GPU) is 100% focused on the first response
        first_audio = await generate_segment(segments[0])
        if first_audio is not None:
            # FIX: Skip fade-in for the very first segment to avoid cutting off the first consonant
            first_audio = AudioService.apply_fade(
                first_audio, fade_in=False, fade_out=True
            )
            last_char = segments[0].strip()[-1] if segments[0].strip() else ""
            silence_sec = pause_map.get(last_char, 0.2)
            silence = AudioService.generate_silence(silence_sec)
            yield np.concatenate([first_audio, silence])

        # 2. Fire the rest sequentially (via Semaphore 1) AFTER the first one has been delivered
        if len(segments) > 1:
            tasks = [asyncio.create_task(generate_segment(s)) for s in segments[1:]]

            for i, task in enumerate(tasks):
                audio = await task
                if audio is not None:
                    seg_text = segments[i + 1]
                    # FIX: Apply both fade-in and fade-out for middle segments to prevent pops
                    audio = AudioService.apply_fade(audio, fade_in=True, fade_out=True)
                    last_char = seg_text.strip()[-1] if seg_text.strip() else ""
                    silence_sec = pause_map.get(last_char, 0.2)
                    silence = AudioService.generate_silence(silence_sec)
                    yield np.concatenate([audio, silence])
