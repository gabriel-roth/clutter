# Clutter

A native macOS menu bar app (no Dock icon) that puts your most recently saved Spotify albums on your desktop, each cover in its own borderless window. The covers are the n newest albums in your Spotify library (n is set under Settings…, 1–100, default 10), checked at launch. Sign-in needs the `user-library-read` and `user-library-modify` scopes; Clutter asks you to sign in again if an earlier sign-in lacks either. Inspired by the original Clutter.

Covers keep their spots and stacking order between launches; new ones appear at random spots on top. Drag a cover to move it, click to bring it to the front, double-click to play the album in Spotify. Hold Option while pointing at a cover to show its close button, which asks before removing the album from your Spotify library; the next-newest album takes its place. Choose Small, Medium, or Large covers from the View menu or the menu bar icon's Cover Size submenu. Positions are saved in `~/Library/Application Support/Clutter/`.

File › Add Currently Playing Album (or the global shortcut you set in Settings…) saves the playing album to your Spotify library, or re-saves it so it's the most recent. At launch Clutter asks you to sign in to Spotify if it isn't already. Sign-in uses the Spotify app whose client ID is in `SpotifyAuthConfig.clutter`; that app must list `clutter://callback` as a redirect URI. Tokens are kept in your login keychain. `scripts/build-app.sh` signs the app with your Apple Development certificate if you have one (Xcode › Settings › Accounts › Manage Certificates), so rebuilds keep access to them; with the ad hoc fallback, macOS asks for your login password after each rebuild.

## Build and run

Requires macOS 14+ and Xcode.

```sh
scripts/test.sh        # run the tests
scripts/build-app.sh   # build build/Clutter.app
open build/Clutter.app
```

Clutter controls Spotify via AppleScript, so the first double-click may prompt you to allow Clutter to control Spotify (System Settings › Privacy & Security › Automation).
