import io
import struct
import wave
from typing import Generator

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

    @staticmethod
    def stream_samples_to_wav(
        sample_generator: Generator[np.ndarray, None, None], volume: float
    ) -> Generator[bytes, None, None]:
        """
        Takes a generator of raw float samples and yields WAV chunks,
        starting with a minimal header for streaming.
        """
        # WAV format configuration (Kokoro standard)
        SAMPLE_RATE = 24000
        N_CHANNELS = 1
        SAMP_WIDTH = 2  # 16-bit PCM

        # 1. Manually construct a 44-byte WAV header for streaming
        # ChunkSize (offsets 4-7) and DataSize (offsets 40-43) are set to 0.
        wav_header = bytearray(44)

        # RIFF Chunk: 'RIFF', ChunkSize=0 (Streaming), 'WAVE'
        struct.pack_into("<4sI4s", wav_header, 0, b"RIFF", 0, b"WAVE")

        # fmt Subchunk: 'fmt ', Size=16, PCM=1, Channels=1, SampleRate=24000, ...
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

        # data Subchunk: 'data', DataSize=0 (Streaming)
        struct.pack_into("<4sI", wav_header, 36, b"data", 0)

        # Yield the header as the first chunk
        yield bytes(wav_header)

        # 2. Stream PCM data chunks
        for samples in sample_generator:
            # a. Apply Volume/Clipping
            if volume != 1.0:
                samples = np.clip(samples * volume, -1.0, 1.0)

            # b. Convert to 16-bit PCM and get bytes
            pcm_data = (samples * 32767).astype(np.int16).tobytes()

            # c. Yield the PCM chunk
            yield pcm_data
