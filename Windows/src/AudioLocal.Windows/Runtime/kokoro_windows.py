#!/usr/bin/env python3
import argparse
import contextlib
import json
import os
import sys

import numpy as np
import soundfile as sf
import torch

try:
    from kokoro import KPipeline
except ImportError as exc:
    raise SystemExit(
        "Missing Kokoro dependencies. Install the bundled runtime or provide "
        "AUDIOLOCAL_KOKORO_*_PYTHON with a Python environment that includes kokoro."
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
    if prefix.startswith("h"):
        return "h"
    if prefix.startswith("i"):
        return "i"
    if prefix.startswith("p"):
        return "p"
    return "a"


def resolve_device(backend: str):
    if backend == "cuda":
        if not torch.cuda.is_available():
            raise RuntimeError("CUDA requested but no CUDA device is available.")
        return "cuda", "CUDA"

    if backend == "directml":
        try:
            import torch_directml
        except ImportError as exc:
            raise RuntimeError("DirectML requested but torch-directml is not installed.") from exc
        return torch_directml.device(), "DirectML"

    return "cpu", "CPU"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--voice", default="af_heart")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--backend", choices=["cuda", "directml", "cpu"], default="cpu")
    args = parser.parse_args()

    with open(args.input, "r", encoding="utf-8") as handle:
        text = handle.read().strip()

    if not text:
        raise SystemExit("No text supplied for Kokoro synthesis.")

    device, label = resolve_device(args.backend)
    with contextlib.redirect_stdout(sys.stderr):
        pipeline = KPipeline(
            lang_code=infer_lang_code(args.voice),
            repo_id="hexgrad/Kokoro-82M",
            device=device)

        chunks = []
        sample_rate = 24000
        for _, _, audio in pipeline(text, voice=args.voice, speed=args.speed):
            array = np.asarray(audio, dtype=np.float32).reshape(-1)
            if array.size:
                chunks.append(array)
            if hasattr(audio, "sample_rate") and audio.sample_rate:
                sample_rate = int(audio.sample_rate)

    if not chunks:
        raise SystemExit("Kokoro produced no audio samples.")

    sf.write(args.output, np.concatenate(chunks), samplerate=sample_rate)
    print(json.dumps({
        "deviceLabel": label,
        "backendLabel": f"Kokoro ({label})"
    }), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
