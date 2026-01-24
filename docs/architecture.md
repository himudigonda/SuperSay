# 🏗️ System Architecture

SuperSay is a hybrid application combining the UI responsiveness of **Swift** with the ML ecosystem of **Python**.

## The Hybrid Bridge

We use a **Local Server Sidecar** approach. 

1.  **Launch**: When the macOS app starts, `LaunchManager` spins up a subprocess executing the compiled `SuperSayServer` binary (or `main.py` in dev mode).
2.  **Health Check**: The Swift app polls `GET /health` until the model is loaded into memory.
3.  **Communication**: All requests are sent via HTTP (REST) to `localhost:8000`.

## Audio Pipeline

One of the hardest problems in TTS is latency. To solve this, we use **Parallel Chunking**:

1.  **Text Normalization (Swift)**: The text is cleaned, URLs are stripped, and ligatures are fixed.
2.  **Request (Swift -> Python)**: The full text is sent to the backend.
3.  **Sentence Splitting (Python)**: The backend splits the text into sentences using Regex look-behinds.
4.  **Inference (ONNX)**: Each sentence is processed through `kokoro-v1.0.onnx`.
5.  **Concatenation (Python)**: 
    *   Audio arrays are merged using NumPy.
    *   Silence padding (0.2s) is added between sentences.
    *   Volume is digitally boosted (clipped to prevent distortion).
6.  **Transmission**: The resulting PCM data is wrapped in a WAV container and sent back to Swift.

## Music Ducking Logic

We do not use standard `AVAudioSession` ducking because it is too aggressive. Instead, we use **AppleScript Automation** via the `osascript` binary.

*   **Pre-Roll**: Record current Music/Spotify volume.
*   **Fade Out**: Smoothly animate volume to 10%.
*   **Play**: Speak the TTS audio.
*   **Post-Roll**: Wait 1 second (Cinematic Buffer), then fade volume back to original level.
