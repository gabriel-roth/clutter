import Testing
@testable import ClutterCore

@Test func scriptTellsSpotifyToPlayTheAlbumURI() {
    let album = Album.all[2]
    #expect(AppleScriptSpotifyPlayer.script(for: album)
        == #"tell application "Spotify" to play track "spotify:album:2akjxkzFolkeV72Yyv5KrM""#)
}
