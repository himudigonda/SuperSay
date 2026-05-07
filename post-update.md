# SuperSay Performance Results — Post-Optimization Round 2

**Date:** 2026-02-26
**Branch:** `claude/perf_`
**System:** Apple M2 Pro | 16 GB | macOS 26.4 | Python 3.11.14

---

## Scenario Matrix (Final)

| # | Scenario | Input | TTFA (ms) | RTF | Throughput | Peak RAM | Chunks |
|---|----------|-------|-----------|-----|------------|----------|--------|
| 1 | Short Many | 15x "The cat sat." (208 chars) | **330.5** | 0.351 | 2.8x | 458 MB | 16 |
| 2 | Short Few | 3x "The cat sat." (40 chars) | **293.5** | 0.300 | 3.3x | 441 MB | 4 |
| 3 | Med Many | 10x 10-word sentence (578 chars) | **305.7** | 0.228 | 4.4x | 523 MB | 11 |
| 4 | Med Few | 3x 10-word sentence (172 chars) | **305.4** | 0.242 | 4.1x | 522 MB | 4 |
| 5 | Long Many | 5x 30-word sentence (813 chars) | **304.0** | 0.200 | 5.0x | 777 MB | 6 |
| 6 | Long Few | 1x 30-word sentence (161 chars) | **295.6** | 0.213 | 4.7x | 773 MB | 2 |
| 7 | Mixed Bag | Mixed lengths (122 chars) | **299.8** | 0.236 | 4.2x | 778 MB | 4 |

**Average TTFA: 304.9 ms**
**Worst-case TTFA: 330.5 ms** (Scenario 1: Short Many)

## Pipeline Stats (10 Mixed Sentences)

| Metric | Value |
|--------|-------|
| TTFA | 311.8 ms |
| Total wall time | 5.05 s |
| Audio duration | 19.45 s |
| RTF | 0.259 |
| Throughput | 3.86x real-time |
| Chunks | 11 |

### Chunk Arrival Times (ms from request start)

```
Chunk  1:   312 ms  (TTFA)
Chunk  2:   726 ms  (+414 ms)
Chunk  3:  1178 ms  (+452 ms)
Chunk  4:  1654 ms  (+476 ms)
Chunk  5:  2138 ms  (+484 ms)
Chunk  6:  2587 ms  (+449 ms)
Chunk  7:  3093 ms  (+506 ms)
Chunk  8:  3575 ms  (+482 ms)
Chunk  9:  4066 ms  (+491 ms)
Chunk 10:  4573 ms  (+507 ms)
Chunk 11:  5047 ms  (+474 ms)
```

**Average inter-chunk interval: 473 ms** (after first chunk)

---

## Improvement Summary (vs Pre-Update Baseline)

| # | Scenario | Before (ms) | After (ms) | Delta | Improvement |
|---|----------|-------------|------------|-------|-------------|
| 1 | Short Many | 366.3 | 330.5 | **-35.8** | 9.8% |
| 2 | Short Few | 353.3 | 293.5 | **-59.8** | 16.9% |
| 3 | Med Many | 393.0 | 305.7 | **-87.3** | 22.2% |
| 4 | Med Few | 406.0 | 305.4 | **-100.6** | 24.8% |
| 5 | Long Many | 395.2 | 304.0 | **-91.2** | 23.1% |
| 6 | Long Few | 380.9 | 295.6 | **-85.3** | 22.4% |
| 7 | Mixed Bag | 315.6 | 299.8 | **-15.8** | 5.0% |
| **Avg** | | **372.9** | **304.9** | **-68.0** | **18.2%** |
| Pipeline | 10 sentences | 408.4 | 311.8 | **-96.6** | 23.7% |

### Worst-case scenario (Med Few) hit the 100ms target: **406.0ms → 305.4ms = -100.6ms**

### Memory improvement
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Min RAM | 678 MB | 441 MB | -35% |
| Max RAM | 990 MB | 778 MB | -21% |

---

## Full Historical Comparison (All 3 Rounds)

| Scenario | Original | Round 1 | Round 2 | Total Saved |
|----------|----------|---------|---------|-------------|
| Short Many | 365 ms | 366 ms | 331 ms | **-34 ms (9%)** |
| Short Few | 683 ms | 353 ms | 294 ms | **-389 ms (57%)** |
| Med Many | 1,080 ms | 393 ms | 306 ms | **-774 ms (72%)** |
| Med Few | 824 ms | 406 ms | 305 ms | **-519 ms (63%)** |
| Long Many | 2,282 ms | 395 ms | 304 ms | **-1,978 ms (87%)** |
| Long Few | 3,257 ms | 381 ms | 296 ms | **-2,961 ms (91%)** |
| Mixed Bag | 397 ms | 316 ms | 300 ms | **-97 ms (24%)** |

---

## What Changed (Round 2)

### Backend (Python)
1. **ONNX Session Optimization** — Custom `SessionOptions` via `Kokoro.from_session()`:
   - `enable_mem_pattern = True` (pre-allocate memory patterns)
   - `enable_cpu_mem_arena = True` (arena allocator)
   - `execution_mode = ORT_SEQUENTIAL` (no inter-op parallelism overhead)
   - `graph_optimization_level = ORT_ENABLE_ALL`
   - `allow_spinning = 1` (threads spin instead of sleeping for lower latency)
   - `intra_op_num_threads = 6` (benchmarked: 6 threads = 271ms min vs auto = 298ms min)

2. **CoreML Attempted and Rejected** — Only 43% of Kokoro's 2,476 graph nodes dispatch to CoreML. Data transfer overhead between CoreML and CPU partitions made it 53% slower. CPU-only remains optimal.

3. **Warm-up Inference** — Single dummy `model.create("Hello.")` during `initialize()` eliminates 2-5x first-request penalty from cold memory allocation and espeak-ng phonemizer initialization.

4. **First Segment Reduced to 2 Words** — `_FIRST_SEG_WORDS`: 4 → 2. Profiled: 2-word ONNX inference ≈ 280ms vs 374ms for 4 words (saves ~94ms on the critical path). The inter-segment silence gap masks any prosody discontinuity.

5. **Pre-computed Silence Arrays** — Common pause durations (0.35s, 0.2s, 0.12s, 0.1s) pre-computed at module level with immutable flags. Eliminates `np.zeros()` allocation per segment.

### Frontend (Swift)
6. **Playback Threshold Halved** — 2,400 bytes (50ms) → 960 bytes (20ms). AVAudioEngine on macOS handles small buffers reliably. Saves ~30ms end-to-end before user hears first audio (not reflected in Python-side benchmark numbers).

### What Didn't Work
- **CoreML Execution Provider**: 53% slower due to CPU⟷CoreML partitioning overhead
- **10 threads**: Slower than 6 threads due to contention on M2 Pro
- **1-2 threads**: Far too slow (1 thread = 1000ms)

## Current Configuration

- `_FIRST_SEG_WORDS = 2` (max words in first segment)
- `_NORMAL_SEG_WORDS = 5` (minimum words before emitting subsequent segments)
- Playback threshold: 20 ms (960 bytes at 24kHz 16-bit mono)
- ONNX: CPU-only, 6 intra-op threads, sequential execution, spinning enabled
- Fade: 50 ms (1200 samples), curves 0.6→1.0
- Inter-segment silence: 0.35s (sentence), 0.2s (colon/semi), 0.12s (comma), 0.1s (default)
- ONNX model: Kokoro-82M (kokoro-v1.0.onnx, 326 MB)
- Inference: single ThreadPoolExecutor (espeak-ng thread safety constraint)
