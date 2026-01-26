# SuperSay Backend (Python)

The high-performance inference engine powering SuperSay. Built with **FastAPI**, **ONNX Runtime**, and **Kokoro-82M**.

## 🚀 Streaming Architecture

Unlike traditional TTS APIs that return a single file, this backend is an **Async Generator**.

1.  **Sentence Splitting**: Regex is used to split long text into semantic sentences.
2.  **Streaming Inference**: As each sentence is processed by `kokoro-v1.0.onnx`, audio bytes are yielded *immediately* to the HTTP stream.
3.  **No Blocking**: This allows the frontend to start playing audio ~200ms after the request is sent, regardless of total text length.

## 📦 Compilation (PyInstaller)

To ship this as a standalone macOS app component, we compile it into a single binary distribution.

```bash
# Compile and Zip
./scripts/compile_backend.sh
```

This script:
1.  Bundles the python interpreter and dependencies.
2.  Includes `kokoro-v1.0.onnx` and `voices-v1.0.bin`.
3.  Embeds a portable `espeak-ng` binary for phonemizer support.
4.  Produces `SuperSayServer.zip` which is injected into the Xcode project.

## 🔌 API Reference

### `POST /speak` (Streaming)

Generates audio stream from text.

**Payload:**
```json
{
  "text": "Hello world",
  "voice": "af_bella",
  "speed": 1.0,
  "volume": 0.8
}
```

**Response:**
*   `200 OK`: `chunked` transfer encoding (WAV/PCM stream).

### `GET /health`

Used by `LaunchManager` to verify the server is active and the model is loaded in memory.
