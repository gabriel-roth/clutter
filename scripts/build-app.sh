#!/bin/bash
# Builds build/Clutter.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Clutter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Clutter" "$APP/Contents/MacOS/Clutter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Artwork/*.jpg "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"
