import io
import struct
import wave

import numpy as np


class AudioService:
    @staticmethod
    def process_samples(samples: np.ndarray, volume: float) -> bytes:
        """
        Clips, normalizes, and encodes raw float samples into a WAV container.
        """
        # 1. Digital Boost / Unconditional Clipping to prevent integer overflow
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
    def apply_fade(
        samples: np.ndarray,
        duration_sec: float = 0.05,
        sample_rate: int = 24000,
        fade_in: bool = True,
        fade_out: bool = True,
    ) -> np.ndarray:
        """
        Applies a linear fade-in and fade-out to the audio samples to prevent popping
        at sentence boundaries.
        """
        if len(samples) == 0:
            return samples

        # FIX: Operate on a copy to ensure we don't mutate shared ONNX memory
        samples = samples.copy()
        fade_samples = int(duration_sec * sample_rate)

        # If the audio is shorter than 2x fade, just fade the whole thing to center
        if len(samples) < 2 * fade_samples:
            fade_samples = len(samples) // 2

        # Apply Fade In
        if fade_in and fade_samples > 0:
            fade_in_curve = np.linspace(0.0, 1.0, fade_samples).astype(np.float32)
            samples[:fade_samples] *= fade_in_curve

        # Apply Fade Out
        if fade_out and fade_samples > 0:
            fade_out_curve = np.linspace(1.0, 0.0, fade_samples).astype(np.float32)
            samples[-fade_samples:] *= fade_out_curve

        return samples

    @staticmethod
    def generate_silence(
        duration_sec: float = 0.2, sample_rate: int = 24000
    ) -> np.ndarray:
        return np.zeros(int(duration_sec * sample_rate), dtype=np.float32)

    @staticmethod
    async def stream_samples_to_wav(sample_generator, volume: float):
        """
        Takes an async generator of raw float samples and yields WAV chunks,
        starting with a minimal header for streaming.
        """
        # WAV format configuration (Kokoro standard)
        SAMPLE_RATE = 24000
        N_CHANNELS = 1
        SAMP_WIDTH = 2  # 16-bit PCM

        # 1. Manually construct a 44-byte WAV header for streaming
        wav_header = bytearray(44)
        struct.pack_into("<4sI4s", wav_header, 0, b"RIFF", 0, b"WAVE")
        byte_rate = SAMPLE_RATE * N_CHANNELS * SAMP_WIDTH
        block_align = N_CHANNELS * SAMP_WIDTH
        struct.pack_into(
            "<4sIHHIIHH",
            wav_header,
            12,
            b"fmt ",
            16,
            1,
            N_CHANNELS,
            SAMPLE_RATE,
            byte_rate,
            block_align,
            SAMP_WIDTH * 8,
        )
        struct.pack_into("<4sI", wav_header, 36, b"data", 0)

        yield bytes(wav_header)

        # 2. Stream PCM data chunks - use 'async for'
        async for samples in sample_generator:
            # FIX: Unconditionally clip to prevent integer overflow pops/screeches!
            samples = np.clip(samples * volume, -1.0, 1.0)
            pcm_data = (samples * 32767).astype(np.int16).tobytes()
            yield pcm_data
