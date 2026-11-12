---
title: AnXinBan Taiwanese ASR
emoji: 🎙️
colorFrom: green
colorTo: yellow
sdk: docker
app_port: 7860
models:
  - MediaTek-Research/Breeze-ASR-26
---
Transcribes Taiwanese recordings with the original Breeze-ASR-26 weights on CPU.
POST a browser recording as binary data to /transcribe to receive a JSON text field.
Audio is decoded in memory. The service accepts one recording at a time.
