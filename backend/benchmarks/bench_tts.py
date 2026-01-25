"""Benchmarks for TTS engine operations."""
from unittest.mock import MagicMock, patch
import numpy as np
import pytest
from app.services.tts import TTSEngine


class MockKokoro:
    """Mock Kokoro model for benchmarking."""
    def create(self, text, voice, speed, lang):
        # Simulate realistic audio output (1 second at 24kHz)
        return np.random.uniform(-0.5, 0.5, 24000).astype(np.float32), None


@pytest.mark.benchmark
def test_bench_tts_sentence_splitting():
    """Benchmark text preprocessing and sentence splitting."""
    with patch.object(TTSEngine, "_model", MockKokoro()):
        text = "Hello world. This is a test! How are you? I'm fine, thanks. What about you?"
        
        # Generate all chunks
        chunks = list(TTSEngine.generate(text, "af_bella", 1.0))
        
        # Should have audio chunks plus silence between them
        assert len(chunks) > 0


@pytest.mark.benchmark
def test_bench_tts_long_text():
    """Benchmark processing longer text passages."""
    with patch.object(TTSEngine, "_model", MockKokoro()):
        # Simulate a paragraph of text
        text = " ".join([
            "This is a benchmark for testing text-to-speech performance.",
            "We want to measure how efficiently the engine processes longer passages.",
            "The system should handle multiple sentences gracefully.",
            "Performance matters for real-time speech synthesis.",
            "Let's make sure the benchmarks capture realistic usage patterns."
        ])
        
        chunks = list(TTSEngine.generate(text, "af_bella", 1.0))
        assert len(chunks) > 0


@pytest.mark.benchmark
def test_bench_tts_speed_variations():
    """Benchmark TTS with different speed settings."""
    with patch.object(TTSEngine, "_model", MockKokoro()):
        text = "Testing different speech speeds for performance."
        
        for speed in [0.8, 1.0, 1.2]:
            chunks = list(TTSEngine.generate(text, "af_bella", speed))
            assert len(chunks) > 0
