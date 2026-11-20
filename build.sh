#!/bin/bash
# Builds "Audio Router.app". By default also installs it to /Applications and launches it.
#
#   ./build.sh               build, install, launch
#   ./build.sh --no-install  just build into ./build
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift not found. Install the command line tools: xcode-select --install"
  exit 1
fi

echo "▸ Compiling (release)…"
swift build -c release --product AudioRouter
BIN="$(swift build -c release --show-bin-path)/AudioRouter"

APP="build/Audio Router.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AudioRouter"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - "$APP"

if [[ $INSTALL == 0 ]]; then
  echo "✓ Built $APP"
  exit 0
fi

echo "▸ Installing to /Applications…"
pkill -x AudioRouter 2>/dev/null || true
rm -rf "/Applications/Audio Router.app"
cp -R "$APP" /Applications/
open "/Applications/Audio Router.app"
echo "✓ Done. Look for the speaker icon in your menu bar."
