import Foundation

@MainActor
public protocol SpotifyPlayer {
    func play(_ album: Album)
}

/// Plays albums through the Spotify desktop app's AppleScript dictionary.
public struct AppleScriptSpotifyPlayer: SpotifyPlayer {
    public init() {}

    public nonisolated static func script(for album: Album) -> String {
        #"tell application "Spotify" to play track "\#(album.spotifyURI)""#
    }

    public func play(_ album: Album) {
        var error: NSDictionary?
        NSAppleScript(source: Self.script(for: album))?.executeAndReturnError(&error)
        if let error {
            NSLog("Clutter: couldn't play %@: %@", album.title, error)
        }
    }
}
