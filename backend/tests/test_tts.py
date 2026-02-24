from unittest.mock import MagicMock, patch

import numpy as np
import pytest
from app.services.audio import AudioService
from app.services.tts import TTSEngine


class MockKokoro:
    def create(self, text, voice, speed, lang):
        # Return dummy audio (1 second of ones)
        return np.ones(24000, dtype=np.float32), None


@pytest.fixture
def mock_kokoro():
    return MockKokoro()


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
        text = "Line one\nLine two"
        mock_model = MagicMock()
        mock_model.create.return_value = (np.ones(100), None)
        TTSEngine._model = mock_model

        gen = TTSEngine.generate(text, "af_bella", 1.0)
        async for _ in gen:
            pass

        # Newlines are replaced by space, so it should be one sentence if no punctuation
        assert mock_model.create.call_count == 1
        call_args = mock_model.create.call_args[0]
        assert "Line one Line two" in call_args[0]


@pytest.mark.asyncio
async def test_tts_engine_not_initialized():
    TTSEngine._model = None
    with pytest.raises(RuntimeError, match="Model not initialized"):
        gen = TTSEngine.generate("test", "af_bella", 1.0)
        async for _ in gen:
            pass
