# SuperSay Backend (Python)

The inference engine powering SuperSay. Built with **FastAPI** and **ONNX Runtime**.

## 🛠️ Setup

We recommend using [uv](https://github.com/astral-sh/uv) for lightning-fast dependency management.

```bash
# 1. Install dependencies
uv sync

# 2. Download Models (Required)
# Place these in the backend/ root
# - kokoro-v1.0.onnx
# - voices-v1.0.bin
```

## 🔌 API Reference

### `POST /speak`

Generates audio from text.

**Payload:**
```json
{
  "text": "Hello world",
  "voice": "af_bella",
  "speed": 1.0,
  "volume": 1.0
}
```

**Response:**
*   `200 OK`: `audio/wav` binary stream.
*   `500 Error`: Text too long or model failure.

### `GET /health`

Used by the Swift frontend to check if the server is ready to accept requests.
