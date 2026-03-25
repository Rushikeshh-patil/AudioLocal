#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PYTHON="${KOKORO_SOURCE_PYTHON:-$REPO_ROOT/.venv-kokoro/bin/python3}"
RUNTIME_OUTPUT_DIR="${1:-${KOKORO_RUNTIME_OUTPUT_DIR:-}}"

if [[ -z "$RUNTIME_OUTPUT_DIR" ]]; then
  echo "Usage: $0 <runtime-output-dir>" >&2
  exit 1
fi

if [[ ! -x "$SOURCE_PYTHON" ]]; then
  echo "Missing Kokoro Python runtime at $SOURCE_PYTHON" >&2
  echo "Run ./scripts/install_kokoro.sh first." >&2
  exit 1
fi

PYTHON_VERSION="$("$SOURCE_PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
BASE_PREFIX="$("$SOURCE_PYTHON" -c 'import sys; print(sys.base_prefix)')"
PURELIB_DIR="$("$SOURCE_PYTHON" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
HF_HUB_CACHE="$(
  REPO_ROOT="$REPO_ROOT" "$SOURCE_PYTHON" - <<'PY'
import os
from pathlib import Path
from huggingface_hub import constants

repo_root = Path(os.environ["REPO_ROOT"])
local_cache = repo_root / ".kokoro-cache" / "huggingface" / "hub"
print(local_cache if local_cache.exists() else constants.HF_HUB_CACHE)
PY
)"

FRAMEWORK_DIR="$(cd "$BASE_PREFIX/../.." && pwd)"
SOURCE_PYTHON_BIN="$BASE_PREFIX/bin/python$PYTHON_VERSION"
SOURCE_PYTHON_DYLIB="$(otool -L "$SOURCE_PYTHON_BIN" | awk 'NR==2 {print $1}')"
MODEL_CACHE_DIR="$HF_HUB_CACHE/models--hexgrad--Kokoro-82M"

if [[ ! -d "$FRAMEWORK_DIR" ]]; then
  echo "Could not locate the base Python framework for $SOURCE_PYTHON" >&2
  exit 1
fi

if [[ ! -d "$PURELIB_DIR" ]]; then
  echo "Could not locate site-packages at $PURELIB_DIR" >&2
  exit 1
fi

if [[ ! -d "$MODEL_CACHE_DIR" ]]; then
  echo "Missing Kokoro model cache at $MODEL_CACHE_DIR" >&2
  echo "Run ./scripts/install_kokoro.sh first so the model is prefetched." >&2
  exit 1
fi

RUNTIME_OUTPUT_DIR="$(mkdir -p "$(dirname "$RUNTIME_OUTPUT_DIR")" && cd "$(dirname "$RUNTIME_OUTPUT_DIR")" && pwd)/$(basename "$RUNTIME_OUTPUT_DIR")"
rm -rf "$RUNTIME_OUTPUT_DIR"
mkdir -p "$RUNTIME_OUTPUT_DIR"

BUNDLED_FRAMEWORK_DIR="$RUNTIME_OUTPUT_DIR/Python.framework"
BUNDLED_VERSION_DIR="$BUNDLED_FRAMEWORK_DIR/Versions/$PYTHON_VERSION"
BUNDLED_PYTHON_BIN="$BUNDLED_VERSION_DIR/bin/python$PYTHON_VERSION"
BUNDLED_PYTHON_DYLIB="$BUNDLED_VERSION_DIR/Python"
BUNDLED_SITE_PACKAGES="$BUNDLED_VERSION_DIR/lib/python$PYTHON_VERSION/site-packages"
BUNDLED_HF_HOME="$RUNTIME_OUTPUT_DIR/cache/huggingface"
BUNDLED_HF_HUB="$BUNDLED_HF_HOME/hub"
LAUNCHER_PATH="$RUNTIME_OUTPUT_DIR/bin/python3"

ditto "$FRAMEWORK_DIR" "$BUNDLED_FRAMEWORK_DIR"
rm -rf "$BUNDLED_SITE_PACKAGES"
mkdir -p "$(dirname "$BUNDLED_SITE_PACKAGES")"
ditto "$PURELIB_DIR" "$BUNDLED_SITE_PACKAGES"

mkdir -p "$BUNDLED_HF_HUB"
ditto "$MODEL_CACHE_DIR" "$BUNDLED_HF_HUB/models--hexgrad--Kokoro-82M"

install_name_tool -change "$SOURCE_PYTHON_DYLIB" "@executable_path/../Python" "$BUNDLED_PYTHON_BIN"
install_name_tool -id "@executable_path/../Python" "$BUNDLED_PYTHON_DYLIB"
codesign --force --sign - "$BUNDLED_PYTHON_DYLIB" >/dev/null
codesign --force --sign - "$BUNDLED_PYTHON_BIN" >/dev/null

mkdir -p "$(dirname "$LAUNCHER_PATH")"
cat > "$LAUNCHER_PATH" <<SH
#!/bin/sh
set -eu
SCRIPT_DIR="\$(CDPATH= cd -- "\$(dirname "\$0")" && pwd)"
RUNTIME_ROOT="\$(CDPATH= cd -- "\$SCRIPT_DIR/.." && pwd)"
PY_VER="$PYTHON_VERSION"
PY_HOME="\$RUNTIME_ROOT/Python.framework/Versions/\$PY_VER"
export PYTHONHOME="\$PY_HOME"
export PYTHONNOUSERSITE=1
export HF_HOME="\$RUNTIME_ROOT/cache/huggingface"
export HF_HUB_CACHE="\$HF_HOME/hub"
export HUGGINGFACE_HUB_CACHE="\$HF_HUB_CACHE"
export HF_HUB_OFFLINE=1
exec "\$PY_HOME/bin/python\$PY_VER" "\$@"
SH
chmod +x "$LAUNCHER_PATH"

echo
echo "Bundled Kokoro runtime created at:"
echo "  $RUNTIME_OUTPUT_DIR"
echo "Python:"
echo "  $LAUNCHER_PATH"
