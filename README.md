# Clutter

Clutter is a macOS menu bar app that scatters your Spotify albums across your desktop.

This app is inspired by the original Clutter for iTunes by Sprote Research. If you're the author, please contact me at gabe.roth@gmail.com.

## Requirements

- macOS 14 or later
- A Spotify account. Playing albums from Clutter requires Spotify Premium. Clutter asks you to sign in to Spotify at launch if you haven't already.

## How it works

- The covers are your newest saved albums. Choose how many (1–100, default 10) under Settings…
- Double-click a cover to play the album on Spotify on your Mac.
- To remove an album from your Spotify library, and hence from Clutter, hold Option while pointing at a cover, then click the close button.
- Covers keep their positions and stacking order between launches. New covers appear at random spots on top.

## Menu bar icon

- **Click:** hide or show all covers. If they're showing behind other windows, it brings them to the front.
- **Command-click or right-click:** open the menu.
- You can also set a global shortcut for this under Settings…

## Arranging covers

These are in the View menu and the menu bar icon's menu.

- **Small, Medium, Large:** set the cover size.
- **Tidy:** line the covers up in an even grid.
- **Scramble:** scatter the covers in a messy jumble.

## Adding albums

File › Add Currently Playing Album saves the playing album to your library. If it's already saved, it is saved again so it becomes the most recent. You can set a global shortcut for this under Settings…

## Building the app

You need macOS 14 or later and Xcode.

1. Register an app at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard). Add `clutter://callback` as a redirect URI.
2. Put its client ID in `SpotifyAuthConfig.clutter`, in `Sources/ClutterCore/SpotifyAuth.swift`.
3. Build and open the app:

```sh
scripts/build-app.sh   # builds build/Clutter.app
open build/Clutter.app
```

To run the tests, use `scripts/test.sh`.

If you have an Apple Development certificate, the build script signs the app with it. Otherwise macOS asks for your login password after each rebuild.
