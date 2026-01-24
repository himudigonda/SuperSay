import re

import numpy as np
from app.core.config import settings
from app.services.audio import AudioService
from kokoro_onnx import Kokoro


class TTSEngine:
    _instance = None
    _model: Kokoro = None

    @classmethod
    def initialize(cls):
        """Loads the ONNX model into memory."""
        if cls._model is None:
            print(f"[TTS] Loading model from: {settings.MODEL_PATH}")
            try:
                cls._model = Kokoro(settings.MODEL_PATH, settings.VOICES_PATH)
                print("[TTS] ✅ Model Loaded Successfully")
            except Exception as e:
                print(f"[TTS] ❌ Fatal Error: {e}")
                raise e

    @classmethod
    def generate(cls, text: str, voice: str, speed: float) -> np.ndarray:
        if not cls._model:
            raise RuntimeError("Model not initialized. Call initialize() first.")

        # 1. Clean & Split Text
        # Split by punctuation followed by space to preserve flow
        raw_text = text.replace("\n", " ").strip()
        sentences = re.split(r"(?<=[.!?])\s+", raw_text)
        sentences = [s for s in sentences if len(s.strip()) > 0]

        if not sentences:
            sentences = [raw_text]

        combined_audio = []
        silence = AudioService.generate_silence(0.2)

        # 2. Inference Loop
        for i, sentence in enumerate(sentences):
            # Limit token check is handled internally by Kokoro-ONNX usually,
            # but chunking helps latency perception.
            audio, _ = cls._model.create(
                sentence, voice=voice, speed=speed, lang="en-us"
            )

            if audio is not None:
                if i > 0:
                    combined_audio.append(silence)
                combined_audio.append(audio)

        if not combined_audio:
            return None

        return np.concatenate(combined_audio)
