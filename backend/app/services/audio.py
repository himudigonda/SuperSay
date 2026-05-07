import io
import struct
import wave

import numpy as np

# Pre-computed WAV header for streaming (44 bytes, sizes set to zero for streaming)
_WAV_HEADER = bytearray(44)
struct.pack_into("<4sI4s", _WAV_HEADER, 0, b"RIFF", 0, b"WAVE")
struct.pack_into("<4sIHHIIHH", _WAV_HEADER, 12, b"fmt ", 16, 1, 1, 24000, 48000, 2, 16)
struct.pack_into("<4sI", _WAV_HEADER, 36, b"data", 0)
_WAV_HEADER_BYTES = bytes(_WAV_HEADER)

# Pre-computed fade curves (avoid re-allocating on every call)
_FADE_SAMPLES = int(0.05 * 24000)  # 1200 samples at 24kHz
_FADE_IN_CURVE = np.linspace(0.6, 1.0, _FADE_SAMPLES, dtype=np.float32)
_FADE_OUT_CURVE = np.linspace(1.0, 0.6, _FADE_SAMPLES, dtype=np.float32)

# Pre-computed silence arrays for common pause durations (eliminates np.zeros per segment)
_SILENCE_CACHE: dict[float, np.ndarray] = {}
for _dur in (0.35, 0.2, 0.12, 0.1):
    _arr = np.zeros(int(_dur * 24000), dtype=np.float32)
    _arr.flags.writeable = False  # Immutable — safe to share without copies
    _SILENCE_CACHE[_dur] = _arr


class AudioService:
    @staticmethod
    def process_samples(samples: np.ndarray, volume: float) -> bytes:
        """
        Clips, normalizes, and encodes raw float samples into a WAV container.
        """
        samples = np.clip(samples * volume, -1.0, 1.0)
        pcm_data = (samples * 32767).astype(np.int16)

        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(24000)
            wav_file.writeframes(pcm_data.tobytes())

        return buffer.getvalue()

    @staticmethod
    def apply_fade(
        samples: np.ndarray,
        fade_in: bool = True,
        fade_out: bool = True,
    ) -> np.ndarray:
        """
        Applies pre-computed fade curves to prevent popping at sentence boundaries.
        """
        n = len(samples)
        if n == 0:
            return samples

        # Operate on a copy to avoid mutating shared ONNX memory
        samples = samples.copy()
        fade_len = _FADE_SAMPLES

        if n < 2 * fade_len:
            fade_len = n // 2

        if fade_in and fade_len > 0:
            if fade_len == _FADE_SAMPLES:
                samples[:fade_len] *= _FADE_IN_CURVE
            else:
                samples[:fade_len] *= np.linspace(0.6, 1.0, fade_len, dtype=np.float32)

        if fade_out and fade_len > 0:
            if fade_len == _FADE_SAMPLES:
                samples[-fade_len:] *= _FADE_OUT_CURVE
            else:
                samples[-fade_len:] *= np.linspace(1.0, 0.6, fade_len, dtype=np.float32)

        return samples

    @staticmethod
    def get_silence(duration_sec: float, sample_rate: int = 24000) -> np.ndarray:
        """Return a silence array, using the pre-computed cache for common durations."""
        cached = _SILENCE_CACHE.get(duration_sec)
        if cached is not None:
            return cached
        return np.zeros(int(duration_sec * sample_rate), dtype=np.float32)

    @staticmethod
    def generate_silence(
        duration_sec: float = 0.2, sample_rate: int = 24000
    ) -> np.ndarray:
        return np.zeros(int(duration_sec * sample_rate), dtype=np.float32)

    @staticmethod
    async def stream_samples_to_wav(sample_generator, volume: float):
        """
        Takes an async generator of raw float samples and yields WAV chunks,
        starting with a pre-computed header for streaming.
        """
        # 1. Yield pre-computed WAV header immediately (no per-request construction)
        yield _WAV_HEADER_BYTES

        # 2. Stream PCM data chunks
        async for samples in sample_generator:
            samples = np.clip(samples * volume, -1.0, 1.0)
            yield (samples * 32767).astype(np.int16).tobytes()
