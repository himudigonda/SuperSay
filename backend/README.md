# SuperSay Inference Engine (Backend)

The engine is built with **FastAPI** and **ONNX Runtime**, utilizing the **Kokoro-82M** model.

## ⚙️ How it Works

1.  **Phonemization:** Uses `espeak-ng` to convert text to phonemes.
2.  **Inference:** The `kokoro-v1.0.onnx` model converts phonemes to raw audio wave samples.
3.  **Parallelization:** The engine doesn't wait for sentence A to finish before starting sentence B. It uses `anyio.to_thread` to run inference in parallel, yielding chunks as they complete.
4.  **Audio Processing:**
    -   Applies 16-bit PCM encoding.
    -   Applies linear fades to sentence boundaries.
    -   Streams data using `StreamingResponse` with `chunked` transfer encoding.

## 🔌 Internal API

-   `GET /health`: Returns `200 OK` once the 80MB model is fully loaded into RAM.
-   `POST /speak`: Accepts JSON `{text, voice, speed, volume}`. Returns a continuous WAV stream.

## 📦 Compilation

We use a custom PyInstaller spec to bundle `espeak-ng` binaries and the ONNX models. Run `./scripts/compile_backend.sh` to generate the portable distribution.
