#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioLocal"
APP_VERSION="${1:-${APP_VERSION:-1.0.0}}"
APP_BUILD_NUMBER="${2:-${APP_BUILD_NUMBER:-1}}"
TARGET_ARCH="${3:-${TARGET_ARCH:-$(uname -m)}}"
SAFE_VERSION="${APP_VERSION//[^A-Za-z0-9._-]/-}"

normalize_arch() {
  case "$1" in
    arm64|aarch64)
      echo "arm64"
      ;;
    x86_64|amd64)
      echo "x86_64"
      ;;
    *)
      echo "Unsupported architecture: $1" >&2
      exit 1
      ;;
  esac
}

arch_label() {
  case "$1" in
    arm64)
      echo "apple-silicon"
      ;;
    x86_64)
      echo "intel"
      ;;
  esac
}

TARGET_ARCH="$(normalize_arch "$TARGET_ARCH")"
ARCH_LABEL="$(arch_label "$TARGET_ARCH")"
APP_BUNDLE="$REPO_ROOT/dist/build/$ARCH_LABEL/$APP_NAME.app"
ZIP_PATH="$REPO_ROOT/dist/${APP_NAME}-macOS-$ARCH_LABEL-$SAFE_VERSION.zip"
DMG_PATH="$REPO_ROOT/dist/${APP_NAME}-macOS-$ARCH_LABEL-$SAFE_VERSION.dmg"
DMG_STAGE_DIR="$REPO_ROOT/dist/dmg-stage-$ARCH_LABEL"

trap 'rm -rf "$DMG_STAGE_DIR"' EXIT

if [[ "${INCLUDE_BUNDLED_KOKORO:-1}" == "1" && ( ! -x "$REPO_ROOT/.venv-kokoro/bin/python3" || ! -d "$REPO_ROOT/.kokoro-cache/huggingface/hub/models--hexgrad--Kokoro-82M" ) ]]; then
  "$REPO_ROOT/scripts/install_kokoro.sh"
fi

OUTPUT_APP_BUNDLE="$APP_BUNDLE" "$REPO_ROOT/scripts/build_app_bundle.sh" "$APP_VERSION" "$APP_BUILD_NUMBER" "$TARGET_ARCH"

rm -f "$ZIP_PATH" "$ZIP_PATH.sha256" "$DMG_PATH" "$DMG_PATH.sha256"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

rm -rf "$DMG_STAGE_DIR"
mkdir -p "$DMG_STAGE_DIR"
ditto "$APP_BUNDLE" "$DMG_STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo
echo "Release artifacts:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "Checksums:"
echo "  $ZIP_PATH.sha256"
echo "  $DMG_PATH.sha256"
echo "Architecture: $TARGET_ARCH"
