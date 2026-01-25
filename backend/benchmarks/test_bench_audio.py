"""Benchmarks for audio processing operations."""
import numpy as np
import pytest
from app.services.audio import AudioService


@pytest.mark.benchmark
def test_bench_process_samples():
    """Benchmark processing of audio samples with clipping and encoding."""
    # Create realistic audio samples (1 second at 24kHz)
    samples = np.random.uniform(-0.5, 0.5, 24000).astype(np.float32)
    volume = 1.2
    
    # Process samples with volume boost
    wav_data = AudioService.process_samples(samples, volume)
    
    assert len(wav_data) > 0
    assert wav_data[:4] == b"RIFF"


@pytest.mark.benchmark
def test_bench_generate_silence():
    """Benchmark silence generation."""
    duration = 0.5  # half second
    silence = AudioService.generate_silence(duration)
    
    assert len(silence) == 12000  # 0.5 * 24000
    assert np.all(silence == 0)


@pytest.mark.benchmark
def test_bench_stream_samples_to_wav():
    """Benchmark streaming audio chunks to WAV format."""
    def sample_generator():
        # Generate 10 chunks of audio
        for _ in range(10):
            yield np.random.uniform(-0.5, 0.5, 2400).astype(np.float32)
    
    volume = 1.0
    chunks = list(AudioService.stream_samples_to_wav(sample_generator(), volume))
    
    # First chunk should be WAV header
    assert chunks[0][:4] == b"RIFF"
    assert len(chunks) == 11  # header + 10 data chunks
