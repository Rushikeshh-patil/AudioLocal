#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioLocal"
APP_VERSION="${1:-${APP_VERSION:-1.0.0}}"
APP_BUILD_NUMBER="${2:-${APP_BUILD_NUMBER:-1}}"
TARGET_ARCH="${3:-${TARGET_ARCH:-$(uname -m)}}"
OUTPUT_APP_BUNDLE="${OUTPUT_APP_BUNDLE:-$REPO_ROOT/dist/$APP_NAME.app}"
APP_BUNDLE="$OUTPUT_APP_BUNDLE"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RESOURCE_BUNDLE_NAME="AudioLocal_AudioLocal.bundle"
STATIC_ICON_ICNS="$REPO_ROOT/Assets/AudioLocal.icns"
ICON_SCRIPT="$REPO_ROOT/scripts/generate_icon.py"
ICONSET_DIR="$REPO_ROOT/dist/AudioLocal.iconset"
GENERATED_ICON_ICNS="$REPO_ROOT/dist/AudioLocal.icns"

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

TARGET_ARCH="$(normalize_arch "$TARGET_ARCH")"

cd "$REPO_ROOT"

swift build -c release --arch "$TARGET_ARCH"
BIN_DIR="$(swift build -c release --arch "$TARGET_ARCH" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE_SOURCE="$BIN_DIR/$RESOURCE_BUNDLE_NAME"

if [[ -f "$STATIC_ICON_ICNS" ]]; then
  ICON_SOURCE="$STATIC_ICON_ICNS"
elif python3 -c 'import PIL' >/dev/null 2>&1; then
  python3 "$ICON_SCRIPT"
  rm -f "$GENERATED_ICON_ICNS"
  iconutil -c icns "$ICONSET_DIR" -o "$GENERATED_ICON_ICNS"
  ICON_SOURCE="$GENERATED_ICON_ICNS"
else
  echo "Missing $STATIC_ICON_ICNS and Pillow is not installed to regenerate the icon." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$(dirname "$APP_BUNDLE")"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

ditto "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
ditto "$RESOURCE_BUNDLE_SOURCE" "$RESOURCES_DIR/$RESOURCE_BUNDLE_NAME"
ditto "$ICON_SOURCE" "$RESOURCES_DIR/AudioLocal.icns"
ln -s "Contents/Resources/$RESOURCE_BUNDLE_NAME" "$APP_BUNDLE/$RESOURCE_BUNDLE_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AudioLocal</string>
  <key>CFBundleIdentifier</key>
  <string>com.rushikeshpatil.AudioLocal</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$APP_NAME"
if ! /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "Skipping ad-hoc code signing for $APP_BUNDLE." >&2
fi

echo
echo "Built $APP_BUNDLE"
echo "Version: $APP_VERSION ($APP_BUILD_NUMBER)"
echo "Architecture: $TARGET_ARCH"
