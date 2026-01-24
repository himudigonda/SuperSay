import io
import wave

import numpy as np


class AudioService:
    @staticmethod
    def process_samples(samples: np.ndarray, volume: float) -> bytes:
        """
        Clips, normalizes, and encodes raw float samples into a WAV container.
        """
        # 1. Digital Boost / Clipping
        if volume != 1.0:
            samples = np.clip(samples * volume, -1.0, 1.0)

        # 2. Convert to 16-bit PCM
        pcm_data = (samples * 32767).astype(np.int16)

        # 3. Write WAV Header
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav_file:
            wav_file.setnchannels(1)  # Mono
            wav_file.setsampwidth(2)  # 2 bytes = 16-bit
            wav_file.setframerate(24000)  # Kokoro standard
            wav_file.writeframes(pcm_data.tobytes())

        return buffer.getvalue()

    @staticmethod
    def generate_silence(
        duration_sec: float = 0.2, sample_rate: int = 24000
    ) -> np.ndarray:
        return np.zeros(int(duration_sec * sample_rate), dtype=np.float32)
