import asyncio
import concurrent.futures
import gc
import re
import time
from collections import OrderedDict
from typing import AsyncGenerator

import numpy as np
from app.core.config import settings
from app.services.audio import AudioService

KITTEN_VOICES = ["Bella", "Jasper", "Luna", "Bruno", "Rosie", "Hugo", "Kiki", "Leo"]
KITTEN_DEFAULT_VOICE = "Bella"

# Silence padding between segments (same logic as TTSEngine)
_PAUSE_MAP = {".": 0.35, "!": 0.35, "?": 0.35, ":": 0.2, ";": 0.2, ",": 0.12}

_NORMAL_SEG_WORDS = 5


def _split_segments(text: str) -> list[str]:
    """Segment splitting for KittenEngine. Mirrors TTSEngine._split_segments.

    All segments (including the first) are grouped at the same threshold so that
    playback transitions land at natural pauses and don't create audible stalls at
    high speeds. The old 2-word first-segment optimisation caused a jarring gap
    because 2 words at 2× speed play in ~100 ms while the next segment takes ~350 ms
    to generate.
    """
    raw_text = text.replace("\n", " ").strip()
    if not raw_text:
        return []

    raw_parts = [
        s.strip() for s in re.split(r"(?<=[.!?|:;,]) +", raw_text) if s.strip()
    ]

    if not raw_parts:
        return [raw_text]

    segments = []
    temp_seg = ""
    for part in raw_parts:
        temp_seg += (" " + part) if temp_seg else part
        word_count = len(temp_seg.split())
        ends_sentence = temp_seg[-1] in ".!?" if temp_seg else False

        if word_count >= _NORMAL_SEG_WORDS or ends_sentence:
            segments.append(temp_seg.strip())
            temp_seg = ""

    if temp_seg:
        segments.append(temp_seg.strip())

    return segments


class KittenEngine:
    _instance = None
    _model = None
    _executor = None
    _active_variant: str = "nano"  # Track which variant is currently loaded

    _is_initializing: bool = False
    _last_request_time: float = 0.0
    _IDLE_TIMEOUT: float = 300.0

    # Lookahead cache: same pattern as TTSEngine. Populated by prewarm_with_lookahead(),
    # consumed (popped) by generate() on the first segment.
    # Uses LRU eviction: most recently hit entries stay, oldest unused are removed.
    _lookahead_cache: OrderedDict = OrderedDict()
    _MAX_CACHE_ENTRIES: int = 10

    @classmethod
    def touch(cls) -> None:
        cls._last_request_time = time.monotonic()

    @classmethod
    def is_loaded(cls) -> bool:
        return cls._model is not None

    @classmethod
    async def ensure_loaded(cls, variant: str = "nano") -> None:
        # Already loaded with the right variant
        if cls._model is not None and cls._active_variant == variant:
            return
        # Variant changed or cold: do a (re)load
        if cls._is_initializing:
            while cls._is_initializing:
                await asyncio.sleep(0.05)
            # After initialization completes, check if we have the right variant now
            # (another request may have loaded a different variant)
            if cls._model is not None and cls._active_variant == variant:
                return
            # Still don't have the right variant, fall through to load it
        cls._is_initializing = True
        try:
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, lambda: cls.initialize(variant))
        finally:
            cls._is_initializing = False

    @classmethod
    def unload(cls) -> None:
        if cls._model is None:
            return
        idle = time.monotonic() - cls._last_request_time
        print(f"[Kitten] Idle for {idle:.0f}s — unloading model to free RAM")
        cls._model = None
        if cls._executor is not None:
            # Cancel any pending (not yet running) futures to clean up cleanly.
            # wait=False prevents blocking on in-flight tasks; cancel_futures=True
            # ensures pending tasks don't run after unload.
            cls._executor.shutdown(wait=False, cancel_futures=True)
            cls._executor = None
        cls._lookahead_cache.clear()
        gc.collect()
        print("[Kitten] Model unloaded")

    @classmethod
    async def prewarm_with_lookahead(cls, text: str, voice: str, speed: float) -> None:
        """Pre-run inference on the first segment and cache the audio.

        Mirrors TTSEngine.prewarm_with_lookahead(). Called by /prewarm when the
        client sends clipboard text + voice + speed. The next /speak with the
        same first segment + settings pops the cached audio, giving <20ms TTFA.
        """
        if not cls._model or not cls._executor:
            return

        segments = _split_segments(text)
        if not segments:
            return

        first_seg = segments[0].strip()
        key = (first_seg, voice, round(speed, 2))

        if key in cls._lookahead_cache:
            # Move to end to mark as recently used (LRU)
            cls._lookahead_cache.move_to_end(key)
            print(f"[Kitten] Lookahead: already cached '{first_seg[:30]}'")
            return

        print(f"[Kitten] Lookahead: pre-computing '{first_seg[:30]}'...")
        loop = asyncio.get_running_loop()
        try:
            audio = await loop.run_in_executor(
                cls._executor,
                lambda s=first_seg: cls._model.generate(
                    s, voice=voice, speed=speed, clean_text=False
                ),
            )
        except Exception as e:
            print(f"[Kitten] Lookahead Error: {e}")
            return

        if audio is None:
            return

        audio = np.asarray(audio).squeeze()

        # Evict LRU (oldest unused) entry when at capacity
        if len(cls._lookahead_cache) >= cls._MAX_CACHE_ENTRIES:
            cls._lookahead_cache.popitem(last=False)  # Remove least recently used

        cls._lookahead_cache[key] = audio
        cls._lookahead_cache.move_to_end(key)  # Mark as most recently used
        print(f"[Kitten] Lookahead: cached '{first_seg[:30]}'")

    @classmethod
    async def idle_watcher(cls) -> None:
        while True:
            await asyncio.sleep(60)
            if cls._model is None or cls._is_initializing:
                continue
            if cls._last_request_time == 0:
                continue
            if time.monotonic() - cls._last_request_time > cls._IDLE_TIMEOUT:
                cls.unload()

    @classmethod
    def initialize(cls, variant: str = "nano") -> None:
        """Load the KittenTTS model and run a warm-up inference."""
        # Unload if variant changed (frees RAM before loading new model)
        if cls._model is not None and cls._active_variant != variant:
            cls.unload()

        if cls._executor is None:
            cls._executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

        if cls._model is None:
            print(f"[Kitten] Loading {variant} model from local files...")
            try:
                import json
                from kittentts.onnx_model import KittenTTS_1_Onnx  # type: ignore[import]

                # Load config to get speed_priors and voice_aliases
                with open(settings.kitten_config_path(variant)) as f:
                    cfg = json.load(f)

                cls._model = KittenTTS_1_Onnx(
                    model_path=settings.kitten_model_path(variant),
                    voices_path=settings.kitten_voices_path(variant),
                    speed_priors=cfg.get("speed_priors", {}),
                    voice_aliases=cfg.get("voice_aliases", {}),
                )
                cls._active_variant = variant
                print("[Kitten] Model loaded, running warm-up...")
                # Warm-up call returns shape (1, N), squeeze to (N,)
                _ = cls._model.generate(
                    "Hello.", voice=KITTEN_DEFAULT_VOICE, speed=1.0, clean_text=False
                )
                print("[Kitten] Ready")
            except Exception as e:
                print(f"[Kitten] Fatal Error: {e}")
                raise

        cls.touch()

    @classmethod
    async def generate(
        cls, text: str, voice: str, speed: float
    ) -> AsyncGenerator[np.ndarray, None]:
        if not cls._model or not cls._executor:
            raise RuntimeError("KittenEngine not initialized. Call initialize() first.")

        segments = _split_segments(text)
        if not segments:
            return

        loop = asyncio.get_running_loop()

        for i, seg_text in enumerate(segments):
            cls.touch()
            seg_stripped = seg_text.strip()
            audio = None

            # Cache hit: first segment was pre-computed by prewarm_with_lookahead()
            if i == 0:
                key = (seg_stripped, voice, round(speed, 2))
                cached = cls._lookahead_cache.pop(key, None)
                if cached is not None:
                    print(f"[Kitten] Cache hit: streaming '{seg_stripped[:30]}'")
                    audio = cached

            if audio is None:
                try:
                    audio = await loop.run_in_executor(
                        cls._executor,
                        lambda s=seg_stripped: cls._model.generate(
                            s, voice=voice, speed=speed, clean_text=False
                        ),
                    )
                except Exception as e:
                    print(f"[Kitten] Model Error on '{seg_text[:30]}': {e}")
                    continue

                if audio is None:
                    continue

                # KittenTTS_1_Onnx.generate() returns shape (1, N), squeeze to (N,)
                audio = np.asarray(audio).squeeze()

            last_char = seg_stripped[-1] if seg_stripped else ""
            silence_sec = _PAUSE_MAP.get(last_char, 0.1) / speed
            silence = AudioService.get_silence(silence_sec)

            yield np.concatenate([audio, silence])
