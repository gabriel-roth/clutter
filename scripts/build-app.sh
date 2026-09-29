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
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# Package resource bundles go in Contents/Resources, where Xcode's Bundle.module looks for them.
for bundle in "$PRODUCTS"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
# Sign with an Apple Development certificate if there is one (Xcode › Settings › Accounts ›
# Manage Certificates). Its Team ID keeps the Keychain item holding the Spotify sign-in readable by
# every rebuild; an ad hoc signature changes with each build, so macOS asks for the login password.
IDENTITY=$(security find-identity -v -p codesigning | awk '/"Apple Development/ { print $2; exit }')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
