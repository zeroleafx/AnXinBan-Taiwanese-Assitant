import asyncio
import subprocess
from functools import lru_cache

import numpy as np
import torch
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from transformers import pipeline

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["POST"], allow_headers=["Content-Type"])
slot = asyncio.Lock()
sample_rate = 16000


@lru_cache(maxsize=1)
def recognizer():
    return pipeline("automatic-speech-recognition", model="MediaTek-Research/Breeze-ASR-26",
                    device="cpu", dtype=torch.float32)


def transcribe(audio):
    try:
        decoded = subprocess.run(
            ["ffmpeg", "-v", "error", "-protocol_whitelist", "pipe", "-i", "pipe:0",
             "-t", "62", "-vn", "-ac", "1", "-ar", str(sample_rate), "-f", "f32le", "pipe:1"],
            input=audio, capture_output=True, check=True, timeout=20,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise HTTPException(422, "Cannot decode recording")
    samples = np.frombuffer(decoded.stdout, dtype="<f4").copy()
    if not 0 < samples.size <= 61 * sample_rate:
        raise HTTPException(422, "Expected a recording of up to one minute")
    result = recognizer()(samples, chunk_length_s=30,
                          generate_kwargs={"language": "zh", "task": "transcribe"})
    return {"text": result["text"].strip()}


@app.get("/")
def info():
    return {"model": "MediaTek-Research/Breeze-ASR-26", "endpoint": "/transcribe"}


@app.post("/transcribe")
async def recognize(request: Request):
    if slot.locked():
        raise HTTPException(429, "Busy, try again shortly")
    async with slot:
        audio = bytearray()
        async for chunk in request.stream():
            if len(audio) + len(chunk) > 12 * 1024 * 1024:
                raise HTTPException(413, "Recording too large")
            audio.extend(chunk)
        return await asyncio.to_thread(transcribe, audio)
