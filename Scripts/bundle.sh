#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if pmset -g batt | grep -q "Battery Power"; then
  echo "On battery power; not building." >&2
  exit 1
fi

if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift Scripts/make-icon.swift "$ICONSET"
  iconutil --convert icns --output Resources/AppIcon.icns "$ICONSET"
fi

swift build --configuration release --arch arm64 --product Jarvis
BINARY="$(swift build --configuration release --arch arm64 --show-bin-path)/Jarvis"

APP="build/Jarvis.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Jarvis"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

DETECTED="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
IDENTITY="${JARVIS_SIGNING_IDENTITY:-${DETECTED:--}}"
codesign --force --options runtime --entitlements Resources/Jarvis.entitlements --sign "$IDENTITY" "$APP"
echo "Built $APP signed with: $IDENTITY"

if [ "${1:-}" = "--install" ]; then
  pkill -x Jarvis || true
  rm -rf /Applications/Jarvis.app
  cp -R "$APP" /Applications/Jarvis.app
  open /Applications/Jarvis.app
  echo "Installed and launched /Applications/Jarvis.app"
fi
