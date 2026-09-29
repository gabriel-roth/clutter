# Clutter

A native macOS app that puts album covers on your desktop, each in its own borderless window. Drag a cover to move it; double-click it to play the album in Spotify. Inspired by the original Clutter.

The six albums are hard-coded in `Sources/ClutterCore/Album.swift`, with their artwork in `Resources/Artwork`.

## Build and run

Requires macOS 14+ and Xcode.

```sh
scripts/test.sh        # run the tests
scripts/build-app.sh   # build build/Clutter.app
open build/Clutter.app
```

Clutter controls Spotify via AppleScript, so the first double-click may prompt you to allow Clutter to control Spotify (System Settings › Privacy & Security › Automation).
