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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# macOS ties privacy grants (Calendar, Reminders, Music) to the signature.
# A stable identity keeps them across rebuilds; an ad-hoc signature changes
# with every build, so macOS asks again each time.
# Order: NOTCHBOARD_SIGN_IDENTITY, else the first "Apple Development"
# identity in the keychain, else ad hoc.
IDENTITY="${NOTCHBOARD_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development/ && !found { print $2; found = 1 }' || true)"
fi
if [[ -n "$IDENTITY" ]]; then
    echo "Signing with: $IDENTITY"
else
    IDENTITY="-"
    echo "Signing ad hoc (no identity found): macOS will ask for Calendar, Reminders and Music access again."
fi
codesign --force --sign "$IDENTITY" --identifier local.notchboard "$APP"
codesign --verify "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x NotchBoard 2>/dev/null || true
    rm -rf "/Applications/NotchBoard.app"
    cp -R "$APP" "/Applications/"
    # Re-register so Finder and Launchpad pick up the new icon.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/NotchBoard.app"
    echo "Installed to /Applications/NotchBoard.app"
fi
