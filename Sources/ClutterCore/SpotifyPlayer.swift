import Foundation

@MainActor
public protocol SpotifyPlayer {
    func play(_ album: Album)
}

/// Plays albums through the Spotify desktop app's AppleScript dictionary.
public struct AppleScriptSpotifyPlayer: SpotifyPlayer {
    public init() {}

    /// Spotify ignores `play track` while it is still starting up, so keep asking
    /// (for up to about 10 seconds) until it reports that it is playing.
    public nonisolated static func script(for album: Album) -> String {
        """
        tell application "Spotify"
            play track "\(album.spotifyURI)"
            repeat 20 times
                if player state is playing then exit repeat
                delay 0.5
                play track "\(album.spotifyURI)"
            end repeat
        end tell
        """
    }

    /// Scripts run off the main thread so the covers stay responsive while Spotify launches.
    public func play(_ album: Album) {
        let source = Self.script(for: album)
        let title = album.title
        AppleScriptRunner.queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                NSLog("Clutter: couldn't play %@: %@", title, error)
            }
        }
    }
}
