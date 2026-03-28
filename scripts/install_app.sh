#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioLocal"
APP_BUNDLE="$REPO_ROOT/dist/$APP_NAME.app"
HOST_ARCH="$(uname -m)"
INCLUDE_BUNDLED_VOXTRAL="${INCLUDE_BUNDLED_VOXTRAL:-$([[ "$HOST_ARCH" == "arm64" ]] && echo 1 || echo 0)}"

if [[ "${INCLUDE_BUNDLED_KOKORO:-1}" == "1" ]]; then
  if [[ ! -x "$REPO_ROOT/.venv-kokoro/bin/python3" || ! -d "$REPO_ROOT/.kokoro-cache/huggingface/hub/models--hexgrad--Kokoro-82M" ]]; then
    "$REPO_ROOT/scripts/install_kokoro.sh"
  fi
fi

if [[ "$INCLUDE_BUNDLED_VOXTRAL" == "1" && "$HOST_ARCH" == "arm64" ]]; then
  if [[ ! -x "$REPO_ROOT/.venv-voxtral/bin/python3" ]]; then
    "$REPO_ROOT/scripts/install_voxtral_mlx.sh"
  fi
fi

"$REPO_ROOT/scripts/build_app_bundle.sh" "${1:-${APP_VERSION:-1.0.0}}" "${2:-${APP_BUILD_NUMBER:-1}}"

rm -rf "/Applications/$APP_NAME.app"
ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"

echo
echo "Installed /Applications/$APP_NAME.app"
echo "Launch it with:"
echo "  open /Applications/$APP_NAME.app"
