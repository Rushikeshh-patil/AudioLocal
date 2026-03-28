#!/bin/zsh
set -euo pipefail

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Voxtral MLX requires Apple Silicon." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

sign_native_extensions() {
  local root="$1"
  if [[ -d "$root" ]]; then
    find "$root" \( -name '*.so' -o -name '*.dylib' \) -print0 | xargs -0 -n 1 codesign --force --sign - >/dev/null
  fi
}

pick_python() {
  for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      "$candidate" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
      if [[ $? -eq 0 ]]; then
        echo "$candidate"
        return 0
      fi
    fi
  done

  if [[ -x /opt/homebrew/bin/python3.12 ]]; then
    echo "/opt/homebrew/bin/python3.12"
    return 0
  fi

  echo "No Python 3.10+ interpreter found. Install one with: brew install python@3.12" >&2
  return 1
}

PYTHON_BIN="$(pick_python)"

"$PYTHON_BIN" -m venv .venv-voxtral
source .venv-voxtral/bin/activate

python -m pip install --upgrade pip
python -m pip install --upgrade --force-reinstall "git+https://github.com/Blaizzy/mlx-audio.git" soundfile numpy tiktoken
sign_native_extensions "$REPO_ROOT/.venv-voxtral/lib"

echo
echo "Voxtral MLX runtime created."
echo "Use this Python path in the app:"
echo "  $REPO_ROOT/.venv-voxtral/bin/python3"
echo
echo "Download the model separately with:"
echo "  ./scripts/pull_voxtral_mlx_model.sh"
