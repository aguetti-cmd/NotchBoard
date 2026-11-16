#!/bin/bash
# Builds NotchBoard.app into ./build. Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchBoard"
APP="build/NotchBoard.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchBoard"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. macOS ties privacy grants to the signature, so after a
# rebuild it may ask for Calendar, Reminders and Music access again.
codesign --force --sign - --identifier local.notchboard "$APP"
codesign --verify "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x NotchBoard 2>/dev/null || true
    rm -rf "$HOME/Applications/NotchBoard.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed to ~/Applications/NotchBoard.app"
fi
