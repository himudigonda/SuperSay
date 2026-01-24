# SuperSay TTS Backend

**The high-performance AI engine for SuperSay.**

This is a FastAPI-based server that wraps the [Kokoro TTS](https://huggingface.co/hexgrad/Kokoro-82M) model in an ONNX runtime. It handles text sanitization, parallel chunk generation, and digital volume amplification.

## 📦 Requirements

* Python 3.11+
* [uv](https://github.com/astral-sh/uv) (Highly recommended)
* `kokoro-v1.0.onnx`
* `voices-v1.0.bin`

## 🚀 Quick Start

```bash
# Install dependencies and start the server
uv run main.py
```

## 🛠️ API Endpoints

### `POST /speak`

Generates high-fidelity WAV audio from text.

* **Request Body**:
    * `text`: The string to speak.
    * `voice`: (Optional) Voice tag (e.g., `af_bella`).
    * `speed`: (Optional) 0.5 to 2.0.
    * `volume`: (Optional) 0.0 to 1.5.
    * `lang`: (Optional) Language code (`en-us`, `ja-jp`, etc.).

### `GET /health`

Returns the status of the model and server.

### `GET /voices`

Returns a list of all available voices in the binary.

## 🏗️ Architecture

The backend is designed for **parallelism**. Large blocks of text are sent to the backend, which are then split by the Swift client into chunks. The backend processes these chunks concurrently to reduce the "Time to First Word."
