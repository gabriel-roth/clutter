# Clutter

A native macOS app that puts album covers on your desktop, each in its own borderless window. Drag a cover to move it; double-click it to play the album in Spotify; hover and click the × to remove it. Choose Small, Medium, or Large covers from the View menu. Use File › Add Currently Playing Album (or the global shortcut you set in Settings…) to add whatever Spotify is playing. The album list and cover positions are saved in `~/Library/Application Support/Clutter/`. Inspired by the original Clutter.

On first launch Clutter scatters six starter albums (`Album.starters`, artwork in `Resources/Artwork`) across the desktop.

## Build and run

Requires macOS 14+ and Xcode.

```sh
scripts/test.sh        # run the tests
scripts/build-app.sh   # build build/Clutter.app
open build/Clutter.app
```

Clutter controls Spotify via AppleScript, so the first double-click may prompt you to allow Clutter to control Spotify (System Settings › Privacy & Security › Automation).
