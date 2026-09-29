#!/bin/bash
# Builds build/Clutter.app from the Swift package. Needs Xcode (not just the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -scheme Clutter -configuration Release -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData -quiet build
PRODUCTS=build/DerivedData/Build/Products/Release
APP=build/Clutter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/Clutter" "$APP/Contents/MacOS/Clutter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Artwork/*.jpg "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Package resource bundles go in Contents/Resources, where Xcode's Bundle.module looks for them.
for bundle in "$PRODUCTS"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
codesign --force --sign - "$APP"
echo "Built $APP"
