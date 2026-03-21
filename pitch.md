0:00 - The Problem
Cloud TTS APIs are too slow for real-time applications. They cost money and require an internet connection. I talked to colleagues who wanted to turn articles and research papers into audio instantly, but the friction of copy-pasting into a browser was too high.

0:15 - The Solution
I built SuperSay to fix this. It is a completely offline macOS app. It uses a SwiftUI frontend and a Python backend running the Kokoro-82M model.

0:30 - The Engineering
The main problem I had to solve was latency. Waiting for a full document to generate takes too long. I set up a streaming pipeline. The backend processes the first sentence and streams the PCM chunks directly to the native audio engine. Playback starts in under 400 milliseconds. The remaining text processes in the background.

0:45 - The Future
This runs entirely on local silicon. This low-latency architecture is exactly what we need to build voice layers for autonomous applications without cloud API costs. I am writing up a technical report on the memory buffering next.
