# Clutter

Clutter is a macOS menu bar app that scatters your Spotify albums across your desktop.

This app is inspired by the original Clutter for iTunes by Sprote Research. If you're the author, please contact me at gabe.roth@gmail.com.

## Requirements

- macOS 14 or later
- A Spotify account. Playing albums from Clutter requires Spotify Premium. Clutter asks you to sign in to Spotify at launch if you haven't already.

## How it works

- The covers are your newest saved albums. Choose how many (1–200, default 10) under Settings…
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

## Swinsian albums

Clutter can also show albums from [Swinsian](https://swinsian.com). When Swinsian is playing, Add Currently Playing Album adds its album to Clutter instead. (If both apps are playing, Swinsian wins; if neither is, a paused Spotify wins over a paused Swinsian.)

- Swinsian albums count toward the number of covers you chose, and take spots before Spotify albums do. The newest Swinsian albums are shown first.
- Double-click a Swinsian cover to play the album in Swinsian. Clutter replaces Swinsian's playback queue with the album's tracks, in the order of Swinsian's current view. If Swinsian is showing a playlist that doesn't include the album, nothing plays.
- Removing a Swinsian cover removes the album only from Clutter, not from Swinsian's library.
- An album's tracks are found by their album title and album artist (or artist, when there's no album artist).

## Building the app

You need macOS 14 or later and Xcode.

1. Register an app at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard). Add `clutter://callback` as a redirect URI.
2. Build the app with its client ID, then open it:

```sh
CLUTTER_SPOTIFY_CLIENT_ID=<your client ID> scripts/build-app.sh   # builds build/Clutter.app
open build/Clutter.app
```

To run the tests, use `scripts/test.sh`.

If you have an Apple Development certificate, the build script signs the app with it. Otherwise macOS asks for your login password after each rebuild.

## Scripting

`tell application "Clutter" to get has key window` is true when one of Clutter's windows is the key window, which is when Command-comma opens Settings. Unlike `frontmost`, it is true after you click a cover even if another app still owns the menu bar.

`tell application "Clutter" to toggle covers` does what clicking the menu bar icon does. `tell application "Clutter" to add current album` does what File › Add Currently Playing Album does, and returns at once.
