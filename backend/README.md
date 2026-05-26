# SuperSay Inference Engine (Backend)

Local FastAPI service bundled inside the macOS app. Runs on `127.0.0.1:10101` — no external traffic for TTS.

Built with **FastAPI**, **ONNX Runtime**, and the **Kokoro-82M** model. KittenTTS was removed in v2.0 — Kokoro is the sole inference path.

## ⚙️ How it works

1. **Phonemization** — `espeak-ng` converts text to phonemes.
2. **Inference** — `kokoro-v1.0.onnx` converts phonemes to PCM samples. Inference is **sentence-sequential** (single-worker `ThreadPoolExecutor`) to avoid espeak-ng C-level race conditions. Concurrency lives at the streaming layer, not the inference layer.
3. **Streaming** — `StreamingResponse` yields each sentence's PCM as soon as it's ready. The Swift frontend schedules buffers immediately so playback starts within ~200ms of the request.
4. **Audio processing** — 16-bit PCM at 24 kHz, linear fade at every sentence boundary to prevent clicks, configurable speed (0.5×–2.0×) and volume.

## 🎧 Voices

Eight Kokoro voices:

```
af_bella, af_sarah          (American female)
am_adam,  am_michael        (American male)
bf_emma,  bf_isabella       (British female)
bm_george, bm_lewis         (British male)
```

Defined in `app/services/engine_manager.py` (`KOKORO_VOICES`). The server-side telemetry whitelist in `himudigonda.me/lib/supersay-validate.js` mirrors this list — keep them in sync when adding voices.

## 🔌 Internal API

| Endpoint | What it does |
| :--- | :--- |
| `GET /health` | `{status: "ready"/"cold", loaded: bool}` — fast, no inference, used by Swift health polling. |
| `POST /prewarm` | Touches the engine so the next `/speak` doesn't pay the cold-start. |
| `POST /speak` | `{text, voice, speed, volume, lang}` → streaming WAV. |
| `POST /audiobook` | Stage a new audiobook from a PDF upload; returns a page-count estimate. |
| `POST /audiobook/{id}/start` | Begin processing the staged book (Gemini cleaning + Kokoro generation). |
| `POST /audiobook/{id}/cancel` | Halt processing. |
| `POST /audiobook/{id}/retry` | Retry failed pages. |
| `GET  /audiobook/{id}/events` | SSE stream of per-page status (`needs_key`/`cleaning`/`tts`/`done`). |
| `GET  /audiobook/{id}/audio` | The final stitched WAV. |
| `GET  /audiobook/{id}/transcript` | JSON transcript with chapter markers. |
| `GET  /audiobook` | List all audiobooks. |
| `DELETE /audiobook/{id}` | Delete a book + its artifacts. |

All routes carry an `X-Correlation-ID` request header (auto-generated if absent) which is propagated to every log line emitted while the handler runs — see `app/core/logging.py`.

## 🗄️ Storage

- **Audiobook metadata**: SQLite WAL-mode DB at `~/Library/Application Support/com.himudigonda.SuperSay/audiobooks/audiobooks.db`. Legacy `meta.json` files are auto-migrated on first launch. No user analytics live in this database — those go to Supabase (`himudigonda.me`), counts only.
- **Audio files**: WAV under `audiobooks/<book_id>/audio.wav` (single seekable file with chapter markers).

## 🪵 Logging

Structured JSON via `app/core/logging.py` (stdlib only, no `structlog` dependency). Every record carries:

- `ts` ISO-8601 UTC
- `level`
- `logger` (e.g. `supersay.http`, `supersay.main`)
- `cid` — request correlation id (via contextvar)
- whatever `extra={...}` the caller passed

The FastAPI `CorrelationMiddleware` in `app/api/middleware.py` generates `cid` per request (or accepts the inbound `X-Correlation-ID`) and writes a single `http.request` line per request with method/path/status/duration.

## 📦 Compilation

Custom PyInstaller spec bundles `espeak-ng` binaries and the ONNX models. Run `./scripts/compile_backend.sh` to produce the `SuperSayServer` binary; `make backend` zips it into `Resources/SuperSayServer.zip` for the Swift app to extract on first launch.

## 🧪 Tests

```bash
cd backend && uv run pytest -q
# 93 passed in ~5s
```

Coverage includes the new `app/core/logging.py` (JSON shape, non-serializable extras, correlation-id context).
