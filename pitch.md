Hook (opening line)
"Imagine being able to turn any article, research paper, or UI text into natural-sounding audio — instantly — without sending a single byte to the cloud."

Intro
Hi, I'm the founder of SuperSay. We build on-device speech synthesis for macOS that removes cloud latency, cost, and privacy concerns while delivering near-instant playback.

The problem (15s)
Today, developers and power users who want readable audio either send data to costly cloud APIs or wait minutes for long text to synthesize. That latency kills workflow: you can't skim, you can't multitask, and you trade privacy for convenience.

Our solution (25s)
SuperSay is a native macOS app with a SwiftUI frontend and a compact Python backend bundling the Kokoro-82M ONNX model. Instead of waiting for a whole document to finish, our backend generates audio sentence-by-sentence and streams raw PCM to the native audio engine. Playback starts almost immediately and continues seamlessly as the rest of the text is synthesized.

Why it's different (20s)
- Streaming-first: sentence-level generation with per-sentence fades and punctuation-aware pauses avoids clicks and enables sub-second perceived start times.
- Deterministic inference: all model and phonemizer tasks run on a single dedicated worker thread to avoid C-level race conditions and keep memory predictable.
- Fully local: no network, no per-call billing, and the model stays on the user's machine for privacy-sensitive use cases.

Product & traction (20s)
We have a working prototype: backend packaged with PyInstaller, a Swift frontend that extracts and runs the server from Application Support, unit tests, and benchmark scripts. The audio pipeline runs at 24 kHz, outputs 16-bit PCM WAV chunks, and integrates with AVAudioEngine to schedule buffers in real time.

> Business model (15s)
We can pursue a few routes: a freemium desktop app (local model + higher-quality voices as paid add-ons), per-seat enterprise licensing for documentation/UX narration, and SDK/licensing for other macOS apps to embed on-device TTS without cloud dependence.

The ask (10s)
We're seeking seed funding to finalize packaging, expand voice variety, optimize CPU/GPU inference paths, and build an enterprise SDK and pilot customers. With funding we'll ship an App Store-ready product and enterprise integrations within 9–12 months.

Closing (5s)
If you'd like, I can show a 60-second demo, a technical deep-dive on the streaming architecture, or a go-to-market plan next. Thank you.
