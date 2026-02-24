import asyncio
import json
import os
import time

import psutil
from app.services.tts import TTSEngine

# Define our input styles
SCENARIOS = {
    "1_Short_Many": (
        ". ".join(["The cat sat."] * 15),
        "Short sentences (3 words), high volume (15 count)",
    ),
    "2_Short_Few": (
        ". ".join(["The cat sat."] * 3),
        "Short sentences (3 words), low volume (3 count)",
    ),
    "3_Med_Many": (
        ". ".join(["This is a medium length sentence for testing throughput."] * 10),
        "Medium sentences (10 words), high volume (10 count)",
    ),
    "4_Med_Few": (
        ". ".join(["This is a medium length sentence for testing throughput."] * 3),
        "Medium sentences (10 words), low volume (3 count)",
    ),
    "5_Long_Many": (
        ". ".join(
            [
                "This is a very long and complex sentence designed to stress the inference engine by providing a massive amount of phonemes for the ONNX model to process at once."
            ]
            * 5
        ),
        "Long sentences (30 words), high volume (5 count)",
    ),
    "6_Long_Few": (
        "This is a very long and complex sentence designed to stress the inference engine by providing a massive amount of phonemes for the ONNX model to process at once.",
        "Long sentence (30 words), single instance",
    ),
    "7_Mixed_Bag": (
        "Hello. This is a medium length sentence. But here is a very long and complex sentence designed to stress the engine. Done.",
        "Mixed sentence lengths",
    ),
}


async def run_scenario(name, text):
    # Reset/Force GC feeling
    process = psutil.Process(os.getpid())

    start_time = time.perf_counter()
    first_audio_ms = 0
    total_samples = 0
    chunk_count = 0

    # We use a dedicated task for the generator to be precise
    generator = TTSEngine.generate(text, "af_bella", 1.0)

    async for chunk in generator:
        if chunk_count == 0:
            first_audio_ms = (time.perf_counter() - start_time) * 1000
        total_samples += len(chunk)
        chunk_count += 1

    end_time = time.perf_counter()
    wall_time = end_time - start_time
    audio_duration = total_samples / 24000

    return {
        "scenario": name,
        "chars": len(text),
        "ttfa": first_audio_ms,
        "rtf": wall_time / audio_duration if audio_duration > 0 else 0,
        "throughput_x": audio_duration / wall_time if wall_time > 0 else 0,
        "mem_peak": process.memory_info().rss / 1024 / 1024,
        "chunks": chunk_count,
        "wall_time": wall_time,
    }


async def run_detailed_pipeline_stats():
    # Test text: 10 sentences to measure jitter/overlap
    test_text = (
        ". ".join(["This is sentence number " + str(i) for i in range(10)]) + "."
    )
    print("📊 Measuring Jitter & Pipeline Overlap (10 Mixed Sentences)...")

    start = time.perf_counter()
    metrics = {"ttfa": 0, "chunk_times": [], "total_samples": 0}

    count = 0
    async for chunk in TTSEngine.generate(test_text, "af_bella", 1.0):
        now = time.perf_counter()
        if count == 0:
            metrics["ttfa"] = (now - start) * 1000
        metrics["chunk_times"].append((now - start) * 1000)
        metrics["total_samples"] += len(chunk)
        count += 1

    end = time.perf_counter()
    metrics["wall_time"] = end - start
    metrics["audio_dur"] = metrics["total_samples"] / 24000
    metrics["rtf"] = (
        metrics["wall_time"] / metrics["audio_dur"] if metrics["audio_dur"] > 0 else 0
    )

    with open("benchmarks/pipeline_stats.json", "w") as f:
        json.dump(metrics, f, indent=2)
    print("✅ Pipeline Stats saved to benchmarks/pipeline_stats.json")


async def main():
    print("🧪 Initializing Clean-Room Benchmark...")
    TTSEngine.initialize()

    # Intensive Warmup: Get the hardware really hot first
    print("🔥 Pre-heating ANE/GPU...")
    for _ in range(3):
        async for _ in TTSEngine.generate(
            "Initial warm up sequence activated.", "af_bella", 1.0
        ):
            pass

    results = []
    for name, (text, desc) in SCENARIOS.items():
        print(f"🏃 Running: {name}...")
        # Give system a tiny breath between runs to stabilize RAM
        await asyncio.sleep(1)
        res = await run_scenario(name, text)
        res["description"] = desc
        results.append(res)

    # Run detailed pipeline stats one last time
    await run_detailed_pipeline_stats()

    os.makedirs("benchmarks", exist_ok=True)
    with open("benchmarks/results.json", "w") as f:
        json.dump(results, f, indent=2)
    print("\n✅ Matrix Complete. Data saved to benchmarks/results.json")


if __name__ == "__main__":
    asyncio.run(main())
