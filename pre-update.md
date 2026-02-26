# SuperSay Performance Baseline — Pre-Optimization Round 2

**Date:** 2026-02-26
**Branch:** `claude/perf_`
**Commit:** `d05dc6b` (perf: reduce TTFA by up to 87% with aggressive first-segment splitting)
**System:** Apple M2 Pro | 16 GB | macOS 26.4 | Python 3.11.14

---

## Scenario Matrix

| # | Scenario | Input | TTFA (ms) | RTF | Throughput | Peak RAM | Chunks |
|---|----------|-------|-----------|-----|------------|----------|--------|
| 1 | Short Many | 15x "The cat sat." (208 chars) | **366.3** | 0.274 | 3.6x | 678 MB | 15 |
| 2 | Short Few | 3x "The cat sat." (40 chars) | **353.3** | 0.281 | 3.6x | 678 MB | 3 |
| 3 | Med Many | 10x 10-word sentence (578 chars) | **393.0** | 0.228 | 4.4x | 752 MB | 11 |
| 4 | Med Few | 3x 10-word sentence (172 chars) | **406.0** | 0.251 | 4.0x | 764 MB | 4 |
| 5 | Long Many | 5x 30-word sentence (813 chars) | **395.2** | 0.213 | 4.7x | 990 MB | 6 |
| 6 | Long Few | 1x 30-word sentence (161 chars) | **380.9** | 0.229 | 4.4x | 990 MB | 2 |
| 7 | Mixed Bag | Mixed lengths (122 chars) | **315.6** | 0.244 | 4.1x | 990 MB | 4 |

**Average TTFA: 372.9 ms**
**Worst-case TTFA: 406.0 ms** (Scenario 4: Med Few)

## Pipeline Stats (10 Mixed Sentences)

| Metric | Value |
|--------|-------|
| TTFA | 408.4 ms |
| Total wall time | 4.90 s |
| Audio duration | 19.49 s |
| RTF | 0.251 |
| Throughput | 3.98x real-time |
| Chunks | 11 |

### Chunk Arrival Times (ms from request start)

```
Chunk  1:   408 ms  (TTFA)
Chunk  2:   695 ms  (+287 ms)
Chunk  3:  1159 ms  (+464 ms)
Chunk  4:  1611 ms  (+452 ms)
Chunk  5:  2080 ms  (+469 ms)
Chunk  6:  2528 ms  (+448 ms)
Chunk  7:  3000 ms  (+472 ms)
Chunk  8:  3462 ms  (+462 ms)
Chunk  9:  3967 ms  (+505 ms)
Chunk 10:  4425 ms  (+458 ms)
Chunk 11:  4902 ms  (+477 ms)
```

**Average inter-chunk interval: 449 ms** (after first chunk)

## Historical Comparison (Round 1 Optimization)

| Scenario | Original (ms) | After Round 1 (ms) | Improvement |
|----------|---------------|---------------------|-------------|
| Short Many | 365 | 366 | ~0% (noise) |
| Short Few | 683 | 353 | 48% |
| Med Many | 1,080 | 393 | 64% |
| Med Few | 824 | 406 | 51% |
| Long Many | 2,282 | 395 | 83% |
| Long Few | 3,257 | 381 | 88% |
| Mixed Bag | 397 | 316 | 20% |

## Current Configuration

- `_FIRST_SEG_WORDS = 4` (max words in first segment for low TTFA)
- `_NORMAL_SEG_WORDS = 5` (minimum words before emitting subsequent segments)
- Playback threshold: 50 ms (2400 bytes at 24kHz 16-bit mono)
- Fade: 50 ms (1200 samples), curves 0.6→1.0
- Inter-segment silence: 0.35s (sentence), 0.2s (colon/semi), 0.12s (comma), 0.1s (default)
- ONNX model: Kokoro-82M (kokoro-v1.0.onnx, 326 MB)
- Inference: single ThreadPoolExecutor (espeak-ng thread safety constraint)
