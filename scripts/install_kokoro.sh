#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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

"$PYTHON_BIN" -m venv .venv-kokoro
source .venv-kokoro/bin/activate

python -m pip install --upgrade pip
python -m pip install "kokoro>=0.9.4" soundfile numpy

echo
echo "Kokoro environment created."
echo "Use this Python path in the app:"
echo "  $REPO_ROOT/.venv-kokoro/bin/python3"
echo
echo "If phoneme generation fails, install espeak-ng with:"
echo "  brew install espeak-ng"
