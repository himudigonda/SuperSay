import asyncio
import concurrent.futures
import re
from typing import AsyncGenerator

import numpy as np
from app.core.config import settings
from app.services.audio import AudioService
from kokoro_onnx import Kokoro


class TTSEngine:
    _instance = None
    _model: Kokoro = None
    _executor = None  # <--- CHANGED: Don't start threads at import time!

    @classmethod
    def initialize(cls):
        """Loads the ONNX model and ThreadPool into memory."""
        # 1. Initialize the Executor lazily
        if cls._executor is None:
            # 🔒 A dedicated, single background thread for ALL Kokoro/espeak operations.
            # This guarantees espeak-ng never runs concurrently and always stays on the
            # exact same C-thread, eliminating cross-thread memory leaks and hallucinations.
            cls._executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

        # 2. Initialize the Model
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
        if not cls._model or not cls._executor:
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

        # 2. Strict Sequential Generation Loop
        # We removed the 'tasks = [create_task...]' list.
        # We now generate -> yield -> generate -> yield.
        # This keeps memory usage low and prevents espeak from choking on a full queue.
        for i, seg_text in enumerate(segments):
            audio = await generate_segment(seg_text)

            if audio is not None:
                # Logic: Don't fade IN the first segment (keep the attack). Fade IN all others.
                # Always fade OUT to prevent clicks.
                is_first = i == 0

                audio = AudioService.apply_fade(
                    audio, fade_in=not is_first, fade_out=True
                )

                last_char = seg_text.strip()[-1] if seg_text.strip() else ""
                silence_sec = pause_map.get(
                    last_char, 0.2
                )  # Default small pause if no punctuation
                silence = AudioService.generate_silence(silence_sec)

                yield np.concatenate([audio, silence])
