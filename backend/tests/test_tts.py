from unittest.mock import MagicMock, patch

import numpy as np
import pytest
from app.services.audio import AudioService
from app.services.tts import TTSEngine


class MockKokoro:
    def create(self, text, voice, speed, lang):
        # Return dummy audio (1 second of ones)
        return np.ones(24000, dtype=np.float32), None


@pytest.fixture(autouse=True)
def setup_tts_engine():
    # Only initialize the executor for tests, don't load the real model
    import concurrent.futures

    if TTSEngine._executor is None:
        TTSEngine._executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)

    # Reset state including lookahead cache
    TTSEngine._model = None
    TTSEngine._lookahead_cache.clear()
    yield
    TTSEngine._lookahead_cache.clear()


@pytest.mark.asyncio
async def test_tts_engine_sentence_splitting():
    # We want to test that the sentence splitting logic works
    with patch.object(TTSEngine, "_model", MockKokoro()):
        text = "Hello world. This is a test! Does it work?"

        mock_model = MagicMock()
        mock_model.create.return_value = (np.ones(100), None)
        TTSEngine._model = mock_model

        gen = TTSEngine.generate(text, "af_bella", 1.0)
        chunks = []
        async for chunk in gen:
            chunks.append(chunk)

        # "Hello world." "This is a test!" "Does it work?"
        # Each yields ONE atomic chunk (audio + trailing silence)
        # Total chunks = 3
        assert len(chunks) == 3
        assert mock_model.create.call_count == 3


@pytest.mark.asyncio
async def test_tts_engine_empty_text():
    with patch.object(TTSEngine, "_model", MockKokoro()):
        gen = TTSEngine.generate("", "af_bella", 1.0)
        chunks = []
        async for chunk in gen:
            chunks.append(chunk)
        # Yields 0 chunks for empty text
        assert len(chunks) == 0


@pytest.mark.asyncio
async def test_tts_engine_newlines():
    with patch.object(TTSEngine, "_model", MockKokoro()):
        text = "Hi there"
        mock_model = MagicMock()
        mock_model.create.return_value = (np.ones(100), None)
        TTSEngine._model = mock_model

        gen = TTSEngine.generate(text, "af_bella", 1.0)
        async for _ in gen:
            pass

        # "Hi there" is 2 words (== _FIRST_SEG_WORDS), fits in one segment
        assert mock_model.create.call_count == 1
        call_args = mock_model.create.call_args[0]
        assert "Hi there" in call_args[0]


@pytest.mark.asyncio
async def test_tts_engine_fade_logic():
    # Verify that the first segment has fade_in=False and subsequent have fade_in=True
    with patch.object(TTSEngine, "_model", MockKokoro()):
        # "Good morning. How are you today?" → 2 segments:
        # "Good morning." (2 words, ≤ _FIRST_SEG_WORDS) and "How are you today?" (4 words)
        text = "Good morning. How are you today?"

        mock_model = MagicMock()
        mock_model.create.return_value = (np.ones(100), None)
        TTSEngine._model = mock_model

        with patch(
            "app.services.tts.AudioService.apply_fade", wraps=AudioService.apply_fade
        ) as mock_fade:
            gen = TTSEngine.generate(text, "af_bella", 1.0)
            async for _ in gen:
                pass

            assert mock_fade.call_count == 2
            # First call should have fade_in=False
            first_call_args = mock_fade.call_args_list[0]
            assert first_call_args.kwargs["fade_in"] is False
            assert first_call_args.kwargs["fade_out"] is True

            # Second call should have fade_in=True
            second_call_args = mock_fade.call_args_list[1]
            assert second_call_args.kwargs["fade_in"] is True
            assert second_call_args.kwargs["fade_out"] is True


@pytest.mark.asyncio
async def test_tts_engine_not_initialized():
    TTSEngine._model = None
    with pytest.raises(RuntimeError, match="Model not initialized"):
        gen = TTSEngine.generate("test", "af_bella", 1.0)
        async for _ in gen:
            pass


@pytest.mark.asyncio
async def test_lookahead_cache_hit_skips_inference():
    """Cache hit: first segment is served from cache without calling model.create."""
    mock_model = MagicMock()
    mock_model.create.return_value = (np.ones(100), None)
    TTSEngine._model = mock_model

    test_text = "Hello world. Great to meet you all."
    # Derive the exact first segment the way generate() does
    first_seg = TTSEngine._split_segments(test_text)[0]  # "Hello world." with period
    key = (first_seg, "af_bella", round(1.0, 2))
    cached_audio = np.ones(50, dtype=np.float32) * 0.5
    TTSEngine._lookahead_cache[key] = cached_audio

    gen = TTSEngine.generate(test_text, "af_bella", 1.0)
    chunks = []
    async for chunk in gen:
        chunks.append(chunk)

    # model.create must NOT have been called for the first segment (cache hit)
    calls = mock_model.create.call_args_list
    called_texts = [c[0][0] for c in calls]
    assert first_seg not in called_texts, "model.create was called for cached segment"
    # Cache entry must be consumed (popped)
    assert key not in TTSEngine._lookahead_cache


@pytest.mark.asyncio
async def test_prewarm_with_lookahead_populates_cache():
    """prewarm_with_lookahead() stores inference result in _lookahead_cache."""
    mock_model = MagicMock()
    cached_audio = np.ones(200, dtype=np.float32)
    mock_model.create.return_value = (cached_audio, None)
    TTSEngine._model = mock_model

    await TTSEngine.prewarm_with_lookahead("Hello world test phrase", "af_bella", 1.0)

    # First segment from "Hello world test phrase" with _FIRST_SEG_WORDS=2
    expected_seg = "Hello world"
    key = (expected_seg, "af_bella", 1.0)
    assert key in TTSEngine._lookahead_cache
    assert TTSEngine._lookahead_cache[key] is cached_audio
    mock_model.create.assert_called_once_with(expected_seg, "af_bella", 1.0, "en-us")


@pytest.mark.asyncio
async def test_prewarm_with_lookahead_no_op_when_cached():
    """prewarm_with_lookahead() skips inference when key is already cached."""
    mock_model = MagicMock()
    TTSEngine._model = mock_model

    prewarm_text = "Hello world. Extra text."
    # Derive exact first segment to match the cache key generation in prewarm_with_lookahead
    first_seg = TTSEngine._split_segments(prewarm_text)[0]  # "Hello world." with period
    key = (first_seg, "af_bella", 1.0)
    TTSEngine._lookahead_cache[key] = np.ones(50, dtype=np.float32)

    await TTSEngine.prewarm_with_lookahead(prewarm_text, "af_bella", 1.0)

    mock_model.create.assert_not_called()


@pytest.mark.asyncio
async def test_lookahead_cache_evicts_oldest_when_full():
    """When cache is full, the oldest entry is evicted before adding a new one."""
    mock_model = MagicMock()
    mock_model.create.return_value = (np.ones(50, dtype=np.float32), None)
    TTSEngine._model = mock_model

    # Fill cache to capacity
    for i in range(TTSEngine._MAX_CACHE_ENTRIES):
        TTSEngine._lookahead_cache[(f"seg{i}", "af_bella", 1.0)] = np.zeros(10)

    oldest_key = ("seg0", "af_bella", 1.0)
    assert oldest_key in TTSEngine._lookahead_cache

    await TTSEngine.prewarm_with_lookahead("New entry here today", "af_bella", 1.0)

    # Oldest must be gone; total entries stay at MAX_CACHE_ENTRIES
    assert oldest_key not in TTSEngine._lookahead_cache
    assert len(TTSEngine._lookahead_cache) == TTSEngine._MAX_CACHE_ENTRIES
