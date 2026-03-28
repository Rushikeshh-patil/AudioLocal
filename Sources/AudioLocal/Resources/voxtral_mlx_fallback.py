#!/usr/bin/env python3
import argparse
import importlib.util
import os
import sys

import numpy as np
import soundfile as sf

try:
    from mlx_audio.tts.utils import load
except ImportError as exc:
    raise SystemExit(
        "Missing Voxtral MLX dependencies. Install them with "
        "`./scripts/install_voxtral_mlx.sh` or `python3 -m pip install mlx-audio soundfile numpy tiktoken`."
    ) from exc


def ensure_voxtral_loader_available() -> None:
    if importlib.util.find_spec("mlx_audio.tts.models.voxtral_tts") is None:
        raise SystemExit(
            "The installed mlx-audio runtime does not currently expose the Voxtral TTS loader. "
            "Re-run `./scripts/install_voxtral_mlx.sh` to refresh the runtime from the current mlx-audio GitHub build."
        )


def resolve_sample_rate(*objects: object) -> int:
    for obj in objects:
        for attribute in ("sample_rate", "sampling_rate", "sr"):
            value = getattr(obj, attribute, None)
            if value:
                return int(value)
    return 24_000


def ensure_tiktoken_available() -> None:
    if importlib.util.find_spec("tiktoken") is None:
        raise SystemExit(
            "Voxtral MLX needs `tiktoken` for its tokenizer. "
            "Re-run `./scripts/install_voxtral_mlx.sh` to install the missing dependency."
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--model", default="mlx-community/Voxtral-4B-TTS-2603-mlx-bf16")
    parser.add_argument("--voice", default="casual_male")
    args = parser.parse_args()

    if sys.platform != "darwin" or os.uname().machine != "arm64":
        raise SystemExit("Voxtral MLX requires Apple Silicon.")

    with open(args.input, "r", encoding="utf-8") as handle:
        text = handle.read().strip()

    if not text:
        raise SystemExit("No text supplied for Voxtral synthesis.")

    ensure_voxtral_loader_available()
    ensure_tiktoken_available()

    try:
        model = load(args.model)
    except ValueError as exc:
        if "voxtral_tts not supported" in str(exc):
            raise SystemExit(
                "The installed mlx-audio runtime does not currently expose the Voxtral TTS loader. "
                "Re-run `./scripts/install_voxtral_mlx.sh` to refresh the runtime from the current mlx-audio GitHub build."
            ) from exc
        raise
    chunks: list[np.ndarray] = []
    sample_rate = resolve_sample_rate(model)

    try:
        for result in model.generate(text=text, voice=args.voice):
            audio = np.asarray(result.audio, dtype=np.float32).reshape(-1)
            if audio.size:
                chunks.append(audio)
            sample_rate = resolve_sample_rate(result, model)
    except RuntimeError as exc:
        if "Tokenizer not loaded" in str(exc):
            raise SystemExit(
                "Voxtral MLX could not initialize its tokenizer. "
                "Re-run `./scripts/install_voxtral_mlx.sh` to refresh the runtime and install `tiktoken`."
            ) from exc
        raise

    if not chunks:
        raise SystemExit("Voxtral produced no audio samples.")

    print("Voxtral device: MLX")
    sf.write(args.output, np.concatenate(chunks), samplerate=sample_rate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
