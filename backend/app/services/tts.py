import asyncio
import concurrent.futures  # <--- NEW IMPORT
import re
from typing import AsyncGenerator

import numpy as np
from app.core.config import settings
from app.services.audio import AudioService
from kokoro_onnx import Kokoro


class TTSEngine:
    _instance = None
    _model: Kokoro = None

    # 🔒 THE FIX: A dedicated, single background thread for ALL Kokoro/espeak operations.
    # This guarantees espeak-ng never runs concurrently and always stays on the
    # exact same C-thread, eliminating cross-thread memory leaks and hallucinations.
    _executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

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

        # 1. Improved Splitting: Split on . ! ? : ; , but group tiny fragments
        raw_text = text.replace("\n", " ").strip()
        raw_segments = [
            s.strip() for s in re.split(r"(?<=[.!?|:;,]) +", raw_text) if s.strip()
        ]

        segments = []
        temp_seg = ""
        for s in raw_segments:
            temp_seg += (" " + s) if temp_seg else s
            if len(temp_seg.split()) >= 5 or any(temp_seg.endswith(p) for p in ".!?"):
                segments.append(temp_seg.strip())
                temp_seg = ""
        if temp_seg:
            segments.append(temp_seg.strip())

        pause_map = {".": 0.8, "!": 0.8, "?": 0.8, ":": 0.5, ";": 0.5, ",": 0.4}

        async def generate_segment(seg: str):
            try:
                loop = asyncio.get_running_loop()
                # 🔒 Run strictly inside the dedicated single-thread executor
                audio, _ = await loop.run_in_executor(
                    cls._executor,
                    cls._model.create,
                    seg.strip(),
                    voice,
                    speed,
                    "en-us",
                )
                return audio
            except Exception as e:
                print(f"[TTS] ❌ Model Error on '{seg[:20]}': {e}")
                return None

        if not segments:
            return

        # --- OPTIMIZATION: PRIORITY QUEUEING ---
        first_audio = await generate_segment(segments[0])
        if first_audio is not None:
            first_audio = AudioService.apply_fade(
                first_audio, fade_in=False, fade_out=True
            )
            last_char = segments[0].strip()[-1] if segments[0].strip() else ""
            silence_sec = pause_map.get(last_char, 0.2)
            silence = AudioService.generate_silence(silence_sec)
            yield np.concatenate([first_audio, silence])

        if len(segments) > 1:
            # Because the executor has max_workers=1, scheduling them concurrently
            # simply queues them in exact order. They will execute 100% safely.
            tasks = [asyncio.create_task(generate_segment(s)) for s in segments[1:]]

            for i, task in enumerate(tasks):
                audio = await task
                if audio is not None:
                    seg_text = segments[i + 1]
                    audio = AudioService.apply_fade(audio, fade_in=True, fade_out=True)
                    last_char = seg_text.strip()[-1] if seg_text.strip() else ""
                    silence_sec = pause_map.get(last_char, 0.2)
                    silence = AudioService.generate_silence(silence_sec)
                    yield np.concatenate([audio, silence])
