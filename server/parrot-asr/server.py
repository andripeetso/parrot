"""Parrot ASR: speech-to-text for the Mac's Parrot dictation app.

Parrot on the Mac POSTs each recording here first and only falls back to its own on-device
Whisper when this box can't be reached. Parakeet TDT 0.6B v2 (full precision, ONNX) runs on
the CPU, so it never fights ComfyUI for VRAM; ~1 s for 30 s of speech on the 5950X.

  POST /api/transcribe   body: WAV file (any rate, mono or stereo)  -> {"text", "seconds", "elapsed"}
  GET  /health

Word fixes are shared with Voxtype: the [text] replacements table in ~/.config/voxtype/config.toml.
"""
import io
import re
import threading
import time
import tomllib
from pathlib import Path

import numpy as np
import onnx_asr
import soundfile as sf
from fastapi import FastAPI, HTTPException, Request

MODEL_DIR = Path.home() / ".local/share/voxtype/models/parakeet-tdt-0.6b-v2"
VOXTYPE_CONFIG = Path.home() / ".config/voxtype/config.toml"
SAMPLE_RATE = 16_000

app = FastAPI(title="Parrot ASR")
model = onnx_asr.load_model("nemo-parakeet-tdt-0.6b-v2", str(MODEL_DIR), providers=["CPUExecutionProvider"])
lock = threading.Lock()


def replacements() -> list[tuple[re.Pattern, str]]:
    try:
        table = tomllib.loads(VOXTYPE_CONFIG.read_text()).get("text", {}).get("replacements", {})
    except (OSError, tomllib.TOMLDecodeError):
        return []
    return [(re.compile(rf"\b{re.escape(k)}\b", re.IGNORECASE), v) for k, v in table.items()]


def to_16k_mono(audio: np.ndarray, rate: int) -> np.ndarray:
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if rate != SAMPLE_RATE:
        n = int(len(audio) * SAMPLE_RATE / rate)
        audio = np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio)
    return audio.astype(np.float32)


@app.get("/health")
def health():
    return {"ok": True, "model": MODEL_DIR.name}


@app.post("/api/transcribe")
async def transcribe(request: Request):
    body = await request.body()
    try:
        audio, rate = sf.read(io.BytesIO(body), dtype="float32")
    except Exception as exc:
        raise HTTPException(400, f"not an audio file: {exc}")
    audio = to_16k_mono(audio, rate)
    started = time.time()
    with lock:
        text = model.recognize(audio, sample_rate=SAMPLE_RATE) if len(audio) else ""
    for pattern, replacement in replacements():
        text = pattern.sub(replacement, text)
    return {"text": text.strip(), "seconds": round(len(audio) / SAMPLE_RATE, 2), "elapsed": round(time.time() - started, 2)}
