import asyncio
import concurrent.futures
import re
from typing import AsyncGenerator

import numpy as np
import onnxruntime as ort
from app.core.config import settings
from app.services.audio import AudioService
from kokoro_onnx import Kokoro


class TTSEngine:
    _instance = None
    _model: Kokoro = None
    _executor = None

    @classmethod
    def initialize(cls):
        """Loads the ONNX model with optimized session and warms up inference."""
        # 1. Initialize the Executor lazily
        if cls._executor is None:
            # A dedicated, single background thread for ALL Kokoro/espeak operations.
            # This guarantees espeak-ng never runs concurrently and always stays on the
            # exact same C-thread, eliminating cross-thread memory leaks and hallucinations.
            cls._executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

        # 2. Initialize the Model with optimized ONNX session
        if cls._model is None:
            print(f"[TTS] Loading model from: {settings.MODEL_PATH}")
            try:
                sess_options = ort.SessionOptions()
                sess_options.enable_mem_pattern = True
                sess_options.enable_cpu_mem_arena = True
                sess_options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
                sess_options.graph_optimization_level = (
                    ort.GraphOptimizationLevel.ORT_ENABLE_ALL
                )
                # Keep threads spinning for lower latency (trades CPU for speed)
                sess_options.add_session_config_entry(
                    "session.intra_op.allow_spinning", "1"
                )

                # CPU-only: CoreML partitions only 43% of Kokoro's nodes, and the
                # data transfer overhead between CoreML and CPU makes it slower overall
                session = ort.InferenceSession(
                    settings.MODEL_PATH,
                    sess_options,
                    providers=["CPUExecutionProvider"],
                )

                cls._model = Kokoro.from_session(session, settings.VOICES_PATH)
                print("[TTS] Model loaded, running warm-up...")

                # Warm-up: first inference is 2-5x slower due to memory allocation
                # and espeak-ng phonemizer initialization
                cls._model.create("Hello.", "af_bella", 1.0, "en-us")
                print("[TTS] Ready")
            except Exception as e:
                print(f"[TTS] Fatal Error: {e}")
                raise e

    # Maximum words for the first segment (keeps TTFA low).
    # Profiling: 3 words ≈ 358ms, 4 words ≈ 374ms (saves ~16ms)
    _FIRST_SEG_WORDS = 3
    # Minimum words before emitting subsequent segments
    _NORMAL_SEG_WORDS = 5

    @classmethod
    def _split_segments(cls, text: str) -> list[str]:
        """Split text into segments optimized for low TTFA.

        Strategy:
        1. Split on punctuation to get natural sentence boundaries.
        2. If the first natural sentence is short enough, use it as-is (fast + natural).
        3. If the first sentence is too long, force-split at a word boundary.
        4. Subsequent segments use normal grouping for prosody quality.
        """
        raw_text = text.replace("\n", " ").strip()
        if not raw_text:
            return []

        # --- Phase 1: Get natural punctuation-based parts ---
        raw_parts = [
            s.strip() for s in re.split(r"(?<=[.!?|:;,]) +", raw_text) if s.strip()
        ]

        if not raw_parts:
            return [raw_text]

        # --- Phase 2: Build first segment (optimized for speed) ---
        first_part = raw_parts[0]
        first_words = first_part.split()

        segments = []
        remaining_start = 1  # Index into raw_parts for Phase 3

        if len(first_words) <= cls._FIRST_SEG_WORDS:
            # First sentence is already short — use it as-is (fast + natural)
            segments.append(first_part)
        else:
            # First sentence is too long — force-split at word boundary
            segments.append(" ".join(first_words[: cls._FIRST_SEG_WORDS]))
            leftover = " ".join(first_words[cls._FIRST_SEG_WORDS :])
            # Prepend leftover to remaining parts for Phase 3
            raw_parts = [leftover] + raw_parts[1:]
            remaining_start = 0

        # --- Phase 3: Group remaining parts with normal thresholds ---
        temp_seg = ""
        for part in raw_parts[remaining_start:]:
            temp_seg += (" " + part) if temp_seg else part
            word_count = len(temp_seg.split())
            ends_sentence = temp_seg[-1] in ".!?" if temp_seg else False

            if word_count >= cls._NORMAL_SEG_WORDS or ends_sentence:
                segments.append(temp_seg.strip())
                temp_seg = ""

        if temp_seg:
            segments.append(temp_seg.strip())

        return segments

    @classmethod
    async def generate(
        cls, text: str, voice: str, speed: float
    ) -> AsyncGenerator[np.ndarray, None]:
        if not cls._model or not cls._executor:
            raise RuntimeError("Model not initialized. Call initialize() first.")

        segments = cls._split_segments(text)

        if not segments:
            return

        # Pause durations tuned for streaming (shorter = more responsive)
        pause_map = {".": 0.35, "!": 0.35, "?": 0.35, ":": 0.2, ";": 0.2, ",": 0.12}

        loop = asyncio.get_running_loop()

        for i, seg_text in enumerate(segments):
            try:
                audio, _ = await loop.run_in_executor(
                    cls._executor,
                    cls._model.create,
                    seg_text.strip(),
                    voice,
                    speed,
                    "en-us",
                )
            except Exception as e:
                print(f"[TTS] Model Error on '{seg_text[:30]}': {e}")
                continue

            if audio is None:
                continue

            is_first = i == 0

            # Apply fades: skip fade-in on first segment to preserve attack
            audio = AudioService.apply_fade(audio, fade_in=not is_first, fade_out=True)

            # Append inter-segment silence using pre-computed arrays
            last_char = seg_text.strip()[-1] if seg_text.strip() else ""
            silence_sec = pause_map.get(last_char, 0.1)
            silence = AudioService.get_silence(silence_sec)

            yield np.concatenate([audio, silence])
