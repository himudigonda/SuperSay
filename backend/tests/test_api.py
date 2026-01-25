from unittest.mock import patch

import numpy as np
from app.main import app
from app.services.audio import AudioService
from app.services.tts import TTSEngine
from fastapi.testclient import TestClient

client = TestClient(app)


# Helper to mock the generator
def mock_tts_generator(*args, **kwargs):
    # Yield small chunks to simulate stream
    yield np.zeros(12000, dtype=np.float32)
    yield AudioService.generate_silence(0.2)
    yield np.zeros(12000, dtype=np.float32)


@patch.object(TTSEngine, "_model", object())  # Mock model loaded
def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "model": "loaded"}


@patch.object(TTSEngine, "_model", object())
@patch("app.services.tts.TTSEngine.generate", side_effect=mock_tts_generator)
def test_speak_endpoint_streaming(mock_generate):
    payload = {
        "text": "Test streaming",
        "voice": "af_bella",
        "speed": 1.0,
        "volume": 1.0,
    }

    # TestClient.post will invoke the endpoint
    response = client.post("/speak", json=payload)

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"

    # Consume the stream
    content = b"".join(response.iter_bytes())

    # Validate WAV Header (RIFF....WAVE)
    assert content[:4] == b"RIFF"
    assert content[8:12] == b"WAVE"
    # Ensure we got data
    assert len(content) > 100
