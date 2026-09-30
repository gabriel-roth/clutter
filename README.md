# Clutter

Clutter is a macOS menu bar app that scatters your newest Spotify albums across your desktop. Each cover gets its own borderless window. There is no Dock icon.

## Requirements

- macOS 14 or later
- Xcode, to build it
- A Spotify account. Playing albums from Clutter needs Premium.

## Build and run

```sh
scripts/test.sh        # run the tests
scripts/build-app.sh   # build build/Clutter.app
open build/Clutter.app
```

## Signing in

Clutter asks you to sign in to Spotify at launch if you haven't already.

- It requests four permissions: `user-library-read`, `user-library-modify`, `user-read-playback-state`, and `user-modify-playback-state`.
- If an earlier sign-in lacks one of them, Clutter asks you to sign in again.
- Tokens are kept in your login keychain.
- Sign-in uses the Spotify app whose client ID is in `SpotifyAuthConfig.clutter`. That app must list `clutter://callback` as a redirect URI.

`scripts/build-app.sh` signs the app with your Apple Development certificate if you have one (Xcode › Settings › Accounts › Manage Certificates). Rebuilds then keep access to your tokens. With the ad hoc fallback, macOS asks for your login password after each rebuild.

## Which albums appear

- The covers are your newest saved albums.
- Choose how many (1–100, default 10) under Settings…
- The list is checked at launch.

## Using the covers

- **Move:** drag a cover.
- **Bring to front:** click it.
- **Play:** double-click. The album plays in the Spotify app on this Mac, which stays in the background. If Spotify isn't running, Clutter starts it hidden.
- **Remove:** hold Option while pointing at a cover, then click its close button. Clutter asks first, then removes the album from your Spotify library. The next-newest album takes its place.

Covers keep their positions and stacking order between launches. New covers appear at random spots on top. Positions are saved in `~/Library/Application Support/Clutter/`.

## Menu bar icon

- **Click:** hide or show all covers. If they're showing behind other windows, it brings them to the front.
- **Command-click or right-click:** open the menu.
- You can also set a global shortcut for this under Settings…

## Arranging covers

These are in the View menu and the menu bar icon's menu.

- **Small, Medium, Large:** change the cover size.
- **Tidy:** line the covers up in an even grid. Each stays as close as it can to where it was.
- **Scramble:** scatter the covers in a messy jumble.

## Adding albums

File › Add Currently Playing Album saves the playing album to your library. If it's already saved, it is saved again so it becomes the most recent. You can set a global shortcut for this under Settings…

The first time, macOS may ask whether Clutter can control Spotify. Clutter reads the playing album through AppleScript. To change the answer later, go to System Settings › Privacy & Security › Automation.
