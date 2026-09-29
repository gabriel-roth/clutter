import Testing
@testable import ClutterCore

@Test func scriptPlaysTheAlbumURIAndRetriesWhileSpotifyStartsUp() {
    let album = Album.starters[2]
    #expect(AppleScriptSpotifyPlayer.script(for: album) == """
        tell application "Spotify"
            play track "spotify:album:2akjxkzFolkeV72Yyv5KrM"
            repeat 20 times
                if player state is playing then exit repeat
                delay 0.5
                play track "spotify:album:2akjxkzFolkeV72Yyv5KrM"
            end repeat
        end tell
        """)
}
