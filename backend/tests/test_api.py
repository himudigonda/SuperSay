from unittest.mock import MagicMock, patch

import numpy as np
from app.main import app
from fastapi.testclient import TestClient

client = TestClient(app)


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "model": "loaded"}


@patch("app.services.tts.TTSEngine.generate")
def test_speak_endpoint(mock_generate):
    # Mock the AI returning silence
    mock_generate.return_value = np.zeros(24000, dtype=np.float32)

    payload = {"text": "Hello Test", "voice": "af_bella", "speed": 1.0, "volume": 1.0}

    response = client.post("/speak", json=payload)

    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"
    assert len(response.content) > 0
