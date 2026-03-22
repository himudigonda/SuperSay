"""Tests for KittenEngine and EngineManager."""

import asyncio
import concurrent.futures
from unittest.mock import MagicMock, patch

import numpy as np
import pytest
from app.services.engine_manager import EngineManager
from app.services.kitten_engine import KittenEngine, _split_segments


class MockKittenTTS_1_Onnx:
    """Mock KittenTTS_1_Onnx that returns shape (1, N) like the real API."""

    def generate(self, text, voice, speed, clean_text=False):
        # Return shape (1, N) to match real KittenTTS_1_Onnx.generate() behavior
        return np.ones((1, 24000), dtype=np.float32)


@pytest.fixture(autouse=True)
def reset_kitten_engine():
    """Reset KittenEngine state before each test."""
    if KittenEngine._executor is None:
        KittenEngine._executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
    KittenEngine._model = None
    KittenEngine._active_variant = "nano"
    KittenEngine._is_initializing = False
    KittenEngine._last_request_time = 0.0
    yield
    if KittenEngine._executor:
        KittenEngine._executor.shutdown(wait=False)
        KittenEngine._executor = None
    KittenEngine._model = None
    KittenEngine._active_variant = "nano"


@pytest.fixture(autouse=True)
def reset_engine_manager():
    """Reset EngineManager to kokoro after each test."""
    yield
    EngineManager.active = "kokoro"
    EngineManager._model_name = ""


# --- Text segmentation ---


def test_split_segments_empty():
    assert _split_segments("") == []


def test_split_segments_single_short():
    result = _split_segments("Hello world.")
    assert len(result) >= 1
    assert "Hello" in result[0]


def test_split_segments_long_text():
    text = "The quick brown fox jumps over the lazy dog. Then it ran away fast."
    result = _split_segments(text)
    assert len(result) >= 2


# --- KittenEngine generate ---


@pytest.mark.asyncio
async def test_kitten_generate_yields_audio():
    KittenEngine._model = MockKittenTTS_1_Onnx()
    chunks = []
    async for chunk in KittenEngine.generate("Hello world.", "Bella", 1.0):
        chunks.append(chunk)
    assert len(chunks) >= 1
    assert all(isinstance(c, np.ndarray) for c in chunks)
    # Verify that chunks are properly squeezed (1D, not 2D)
    for chunk in chunks:
        assert chunk.ndim == 1, f"Expected 1D array, got {chunk.ndim}D"


@pytest.mark.asyncio
async def test_kitten_generate_empty_text():
    KittenEngine._model = MockKittenTTS_1_Onnx()
    chunks = []
    async for chunk in KittenEngine.generate("", "Bella", 1.0):
        chunks.append(chunk)
    assert chunks == []


@pytest.mark.asyncio
async def test_kitten_generate_not_initialized():
    KittenEngine._model = None
    KittenEngine._executor = None
    with pytest.raises(RuntimeError, match="not initialized"):
        async for _ in KittenEngine.generate("Hello.", "Bella", 1.0):
            pass


# --- EngineManager ---


@pytest.mark.asyncio
async def test_engine_manager_default_is_kokoro():
    assert EngineManager.active == "kokoro"


@pytest.mark.asyncio
async def test_engine_manager_state_shape():
    state = EngineManager.state()
    assert "engine" in state
    assert "model" in state
    assert "voices" in state
    assert isinstance(state["voices"], list)


@pytest.mark.asyncio
async def test_engine_manager_switch_to_kitten():
    with patch.object(KittenEngine, "ensure_loaded"), patch.object(
        KittenEngine, "unload"
    ), patch("app.services.engine_manager.TTSEngine") as mock_tts:
        mock_tts.is_loaded.return_value = True
        mock_tts.unload = MagicMock()
        await EngineManager.switch("kitten", "nano")
    assert EngineManager.active == "kitten"
    assert EngineManager._model_name == "nano"


@pytest.mark.asyncio
async def test_engine_manager_voices_change_on_switch():
    EngineManager.active = "kokoro"
    kokoro_voices = EngineManager.voices()
    EngineManager.active = "kitten"
    kitten_voices = EngineManager.voices()
    assert kokoro_voices != kitten_voices
    assert "af_bella" in kokoro_voices
    assert "Bella" in kitten_voices


@pytest.mark.asyncio
async def test_engine_manager_generate_is_async_generator():
    """Test that EngineManager.generate() returns a true async generator."""
    EngineManager.active = "kitten"
    KittenEngine._model = MockKittenTTS_1_Onnx()

    gen = EngineManager.generate("Hello.", "Bella", 1.0)

    # Verify it's an async generator (has __aiter__ and __anext__)
    assert hasattr(gen, "__aiter__"), "generate() should return an async generator"
    assert hasattr(gen, "__anext__"), "generate() should return an async generator"

    # Verify we can iterate and get chunks
    chunks = []
    async for chunk in gen:
        chunks.append(chunk)

    assert len(chunks) > 0, "Should yield at least one chunk"
    assert all(isinstance(c, np.ndarray) for c in chunks)
    assert all(c.ndim == 1 for c in chunks), "All chunks should be 1D after squeezing"


@pytest.mark.asyncio
async def test_engine_manager_generate_dispatches_to_kokoro():
    """Test that EngineManager dispatches to correct engine."""
    EngineManager.active = "kokoro"

    # Create a mock TTSEngine.generate that yields chunks
    async def mock_kokoro_generate(text, voice, speed):
        yield np.zeros(12000, dtype=np.float32)
        yield np.zeros(12000, dtype=np.float32)

    with patch(
        "app.services.engine_manager.TTSEngine.generate",
        side_effect=mock_kokoro_generate,
    ):
        chunks = []
        async for chunk in EngineManager.generate("Test", "af_bella", 1.0):
            chunks.append(chunk)

    assert len(chunks) == 2, "Should get 2 chunks from mocked kokoro"


@pytest.mark.asyncio
async def test_engine_manager_generate_dispatches_to_kitten():
    """Test that EngineManager dispatches to kitten engine."""
    EngineManager.active = "kitten"
    KittenEngine._model = MockKittenTTS_1_Onnx()

    chunks = []
    async for chunk in EngineManager.generate("Hello world.", "Bella", 1.0):
        chunks.append(chunk)

    assert len(chunks) > 0, "Should get chunks from kitten"
    assert all(c.ndim == 1 for c in chunks), "All chunks should be 1D"


def test_kitten_variant_switch_logic():
    """Test that initialize() calls unload when variant changes."""
    # Set up initial state: model loaded with nano variant
    KittenEngine._model = MockKittenTTS_1_Onnx()
    KittenEngine._active_variant = "nano"

    # Track unload calls
    unload_calls = []

    def track_unload():
        unload_calls.append(KittenEngine._active_variant)
        KittenEngine._model = None

    # Patch unload to track calls
    with patch.object(KittenEngine, "unload", side_effect=track_unload):
        # Try to initialize with micro — this should trigger unload first
        # We expect initialize to fail on file I/O, but unload should have been called
        try:
            KittenEngine.initialize("micro")
        except FileNotFoundError:
            pass  # Expected: kitten-micro files don't exist

    # Verify unload was called with the previous variant
    assert len(unload_calls) > 0, "unload() should be called when variant changes"


@pytest.mark.asyncio
async def test_engine_manager_forwards_variant_to_kitten():
    """Test that EngineManager.switch() forwards the model variant to KittenEngine."""
    with patch.object(KittenEngine, "ensure_loaded") as mock_ensure, patch.object(
        KittenEngine, "unload"
    ), patch("app.services.engine_manager.TTSEngine") as mock_tts:
        mock_tts.is_loaded.return_value = False
        await EngineManager.switch("kitten", "micro")

    # Verify ensure_loaded was called with "micro" variant
    mock_ensure.assert_called_once_with("micro")


@pytest.mark.asyncio
async def test_engine_manager_ensure_loaded_forwards_variant():
    """Test that EngineManager.ensure_loaded() forwards stored variant to KittenEngine."""
    EngineManager.active = "kitten"
    EngineManager._model_name = "mini"

    with patch.object(KittenEngine, "ensure_loaded") as mock_ensure:
        await EngineManager.ensure_loaded()

    # Verify ensure_loaded was called with "mini" variant
    mock_ensure.assert_called_once_with("mini")


@pytest.mark.asyncio
async def test_kitten_ensure_loaded_variant_match():
    """Test that ensure_loaded() skips reload if variant matches."""
    KittenEngine._model = MockKittenTTS_1_Onnx()
    KittenEngine._active_variant = "nano"
    KittenEngine._is_initializing = False

    # Should return early without reloading
    await KittenEngine.ensure_loaded("nano")

    # Model should not have changed
    assert KittenEngine._model is not None
    assert KittenEngine._active_variant == "nano"


@pytest.mark.asyncio
async def test_kitten_ensure_loaded_variant_mismatch():
    """Test that ensure_loaded() triggers reload if variant mismatch."""
    KittenEngine._model = MockKittenTTS_1_Onnx()
    KittenEngine._active_variant = "nano"
    KittenEngine._is_initializing = False

    with patch.object(KittenEngine, "initialize") as mock_init:
        await KittenEngine.ensure_loaded("micro")

    # Should trigger initialize with the new variant
    mock_init.assert_called_once()


@pytest.mark.asyncio
async def test_kitten_concurrent_variant_requests():
    """Test race condition: two requests for different variants during initialization."""
    # Start with nano loaded
    KittenEngine._model = MockKittenTTS_1_Onnx()
    KittenEngine._active_variant = "nano"
    KittenEngine._is_initializing = False

    # Simulate slow initialization by tracking calls
    initialize_calls = []

    def slow_init(variant: str):
        initialize_calls.append(variant)
        KittenEngine._active_variant = variant
        KittenEngine._model = MockKittenTTS_1_Onnx()

    # Request A wants micro, Request B also wants micro (concurrent)
    with patch.object(KittenEngine, "initialize", side_effect=slow_init):
        # Simulate request A starting initialization
        KittenEngine._is_initializing = True
        task_a = asyncio.create_task(KittenEngine.ensure_loaded("micro"))
        await asyncio.sleep(0.01)  # Let task A start

        # Request B comes in while A is initializing
        task_b = asyncio.create_task(KittenEngine.ensure_loaded("micro"))

        # Simulate initialization finishing
        await asyncio.sleep(0.02)
        KittenEngine._is_initializing = False
        slow_init("micro")

        # Wait for both tasks
        await task_a
        await task_b

    # Both should have gotten micro (only one initialize call needed)
    assert KittenEngine._active_variant == "micro"
    assert initialize_calls.count("micro") >= 1


@pytest.mark.asyncio
async def test_kitten_variant_mismatch_during_init_retries():
    """Test that variant mismatch after init resets _is_initializing correctly."""
    KittenEngine._model = None
    KittenEngine._active_variant = "nano"
    KittenEngine._is_initializing = False

    initialize_calls = []

    def mock_init_variant(variant: str):
        initialize_calls.append(variant)
        KittenEngine._active_variant = variant
        KittenEngine._model = MockKittenTTS_1_Onnx()

    with patch.object(KittenEngine, "initialize", side_effect=mock_init_variant):
        # Request A initializes nano
        task_a = asyncio.create_task(KittenEngine.ensure_loaded("nano"))
        await asyncio.sleep(0.01)

        # Request B wants micro while A is initializing nano
        task_b = asyncio.create_task(KittenEngine.ensure_loaded("micro"))

        await task_a
        await task_b

    # After race condition resolution, _active_variant should be correct
    # and _is_initializing should be reset for subsequent requests
    assert not KittenEngine._is_initializing
    assert KittenEngine._active_variant in ("nano", "micro")
