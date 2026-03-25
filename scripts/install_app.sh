#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioLocal"
APP_BUNDLE="$REPO_ROOT/dist/$APP_NAME.app"
"$REPO_ROOT/scripts/build_app_bundle.sh" "${1:-${APP_VERSION:-1.0.0}}" "${2:-${APP_BUILD_NUMBER:-1}}"

rm -rf "/Applications/$APP_NAME.app"
ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"

echo
echo "Installed /Applications/$APP_NAME.app"
echo "Launch it with:"
echo "  open /Applications/$APP_NAME.app"
