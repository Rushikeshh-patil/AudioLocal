#!/usr/bin/env python3
import argparse
import os
import sys

os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

import numpy as np
import soundfile as sf
import torch

try:
    from kokoro import KPipeline
except ImportError as exc:
    raise SystemExit(
        "Missing Kokoro dependencies. Install them with "
        "`./scripts/install_kokoro.sh` or `python3 -m pip install \"kokoro>=0.9.4\" soundfile numpy`."
    ) from exc


def infer_lang_code(voice: str) -> str:
    prefix = voice.split("_", 1)[0].lower()
    if prefix.startswith("a"):
        return "a"
    if prefix.startswith("b"):
        return "b"
    if prefix.startswith("j"):
        return "j"
    if prefix.startswith("z"):
        return "z"
    return "a"


def candidate_devices() -> list[str]:
    devices: list[str] = []
    if torch.backends.mps.is_available():
        devices.append("mps")
    if torch.cuda.is_available():
        devices.append("cuda")
    devices.append("cpu")
    return devices


def synthesize_with_device(text: str, voice: str, speed: float, device: str) -> tuple[np.ndarray, int]:
    pipeline = KPipeline(lang_code=infer_lang_code(voice), device=device)
    chunks = []
    sample_rate = None

    for _, _, audio in pipeline(text, voice=voice, speed=speed):
        array = np.asarray(audio, dtype=np.float32).reshape(-1)
        if array.size:
            chunks.append(array)
        if sample_rate is None and hasattr(audio, "sample_rate"):
            sample_rate = int(audio.sample_rate)

    if not chunks:
        raise RuntimeError("Kokoro produced no audio samples.")

    return np.concatenate(chunks), sample_rate or 24000


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    args = parser.parse_args()

    with open(args.input, "r", encoding="utf-8") as handle:
        text = handle.read().strip()

    if not text:
        raise SystemExit("No text supplied for Kokoro synthesis.")

    errors = []
    for device in candidate_devices():
        try:
            full_audio, sample_rate = synthesize_with_device(
                text=text,
                voice=args.voice,
                speed=args.speed,
                device=device,
            )
            print(f"Kokoro device: {device}")
            sf.write(args.output, full_audio, samplerate=sample_rate)
            return 0
        except Exception as exc:
            errors.append(f"{device}: {exc}")

    raise SystemExit("Kokoro synthesis failed on all devices. " + " | ".join(errors))


if __name__ == "__main__":
    sys.exit(main())
