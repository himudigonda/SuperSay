"""Benchmarks for API endpoints."""

from unittest.mock import patch
import numpy as np
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.services.tts import TTSEngine

client = TestClient(app)


def mock_tts_generator(*args, **kwargs):
    """Mock TTS generator for benchmarking."""
    # Yield realistic audio chunks
    for _ in range(3):
        yield np.random.uniform(-0.5, 0.5, 12000).astype(np.float32)


@pytest.mark.benchmark
@patch.object(TTSEngine, "_model", object())
def test_bench_health_check():
    """Benchmark health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200


@pytest.mark.benchmark
@patch.object(TTSEngine, "_model", object())
@patch("app.services.tts.TTSEngine.generate", side_effect=mock_tts_generator)
def test_bench_speak_endpoint(mock_generate):
    """Benchmark the main speak endpoint with streaming."""
    payload = {
        "text": "This is a performance test for the speak endpoint.",
        "voice": "af_bella",
        "speed": 1.0,
        "volume": 1.0,
    }

    response = client.post("/speak", json=payload)
    assert response.status_code == 200

    # Consume the stream
    content = b"".join(response.iter_bytes())
    assert len(content) > 0


@pytest.mark.benchmark
@patch.object(TTSEngine, "_model", object())
@patch("app.services.tts.TTSEngine.generate", side_effect=mock_tts_generator)
def test_bench_speak_long_text(mock_generate):
    """Benchmark speak endpoint with longer text input."""
    payload = {
        "text": " ".join(
            [
                "This is a longer text to benchmark.",
                "It contains multiple sentences.",
                "We want to measure performance with realistic input.",
                "The API should handle this efficiently.",
            ]
        ),
        "voice": "af_bella",
        "speed": 1.0,
        "volume": 1.0,
    }

    response = client.post("/speak", json=payload)
    assert response.status_code == 200

    content = b"".join(response.iter_bytes())
    assert len(content) > 0
