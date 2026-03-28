#!/bin/zsh
set -euo pipefail

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Voxtral MLX requires Apple Silicon." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${VOXTRAL_SOURCE_PYTHON:-$REPO_ROOT/.venv-voxtral/bin/python3}"
MODEL_ID="${VOXTRAL_MODEL_ID:-mlx-community/Voxtral-4B-TTS-2603-mlx-bf16}"
HF_HOME_DEFAULT="$HOME/Library/Application Support/AudioLocal/VoxtralModels/huggingface"
export VOXTRAL_MODEL_ID="$MODEL_ID"
export HF_HOME="${HF_HOME:-$HF_HOME_DEFAULT}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
export HUGGINGFACE_HUB_CACHE="${HUGGINGFACE_HUB_CACHE:-$HF_HUB_CACHE}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Missing Voxtral MLX Python runtime at $PYTHON_BIN" >&2
  echo "Run ./scripts/install_voxtral_mlx.sh first." >&2
  exit 1
fi

mkdir -p "$HF_HUB_CACHE"

"$PYTHON_BIN" - <<'PY'
import os
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id=os.environ.get("VOXTRAL_MODEL_ID", "mlx-community/Voxtral-4B-TTS-2603-mlx-bf16"),
    resume_download=True,
)
PY

echo
echo "Voxtral MLX model downloaded."
echo "HF_HOME:"
echo "  $HF_HOME"
echo "HF_HUB_CACHE:"
echo "  $HF_HUB_CACHE"
