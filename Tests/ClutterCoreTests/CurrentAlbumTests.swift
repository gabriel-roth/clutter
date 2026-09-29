import Foundation
import Testing
@testable import ClutterCore

private let playingOutput = """
    spotify:track:2504XYM0mWWPEVMD3XlLje
    The Singer in My Band
    This Is Lorelei
    This Is Lorelei
    https://i.scdn.co/image/ab67616d0000b273c456875e0df6d8195f4b5545
    """

// Trimmed from the real page at https://open.spotify.com/track/2504XYM0mWWPEVMD3XlLje
private let trackHTML = #"<html><head><meta property="og:title" content="Watching Heaven Fall"/><meta property="og:description" content="This Is Lorelei · The Singer in My Band · Song · 2026"/><meta name="music:album" content="https://open.spotify.com/album/24cxezS5U9YTFapgKpYG16"/><meta name="music:album:track" content="4"/></head></html>"#

@Test func parsesAPlayingTrack() {
    #expect(NowPlaying.parse(playingOutput) == NowPlaying(
        trackURI: "spotify:track:2504XYM0mWWPEVMD3XlLje",
        album: "The Singer in My Band",
        artist: "This Is Lorelei",
        artworkURL: URL(string: "https://i.scdn.co/image/ab67616d0000b273c456875e0df6d8195f4b5545")!
    ))
    #expect(NowPlaying.parse(playingOutput)?.trackID == "2504XYM0mWWPEVMD3XlLje")
}

@Test func fallsBackToTrackArtistWhenAlbumArtistIsEmpty() {
    let output = "spotify:track:abc\nAlbum\n\nTrack Artist\nhttps://i.scdn.co/image/x"
    #expect(NowPlaying.parse(output)?.artist == "Track Artist")
}

@Test(arguments: [
    "",                                                                   // Spotify not running or stopped
    "spotify:episode:abc\nShow\nHost\nHost\nhttps://i.scdn.co/image/x",   // podcast
    "spotify:ad:abc\nAd\n\n\nhttps://i.scdn.co/image/x",                  // advert
    "spotify:local:Artist:Album:Song:180\nAlbum\nArtist\nArtist\n",       // local file, no artwork
    "spotify:track:abc\nAlbum\nArtist",                                   // too few lines
])
func rejectsAnythingButASpotifyTrack(output: String) {
    #expect(NowPlaying.parse(output) == nil)
}

@Test func scriptDoesNotLaunchSpotify() {
    #expect(NowPlaying.script.hasPrefix(#"if application "Spotify" is running then"#))
}

@Test func findsTheAlbumURIInTheTrackPage() {
    #expect(TrackPage.albumURI(fromHTML: trackHTML) == "spotify:album:24cxezS5U9YTFapgKpYG16")
}

@Test func pageWithoutAnAlbumTagHasNoAlbumURI() {
    #expect(TrackPage.albumURI(fromHTML: "<html><head></head></html>") == nil)
}

@Test func trackPageURL() {
    #expect(TrackPage.url(forTrackID: "2504XYM0mWWPEVMD3XlLje").absoluteString == "https://open.spotify.com/track/2504XYM0mWWPEVMD3XlLje")
}

/// Serves `pages` by exact URL; anything else fails, which catches wrong URLs.
private func fakeHTTP(_ pages: [String: Data]) -> @Sendable (URL) async throws -> Data {
    { url in
        guard let data = pages[url.absoluteString] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

@Test func fetchesThePlayingAlbumAndItsArtwork() async throws {
    let fetcher = CurrentAlbumFetcher(
        nowPlaying: { playingOutput },
        http: fakeHTTP([
            "https://open.spotify.com/track/2504XYM0mWWPEVMD3XlLje": Data(trackHTML.utf8),
            "https://i.scdn.co/image/ab67616d0000b273c456875e0df6d8195f4b5545": Data("jpeg".utf8),
        ])
    )
    let (album, artwork) = try await fetcher.fetch()
    #expect(album == Album(
        title: "The Singer in My Band",
        artist: "This Is Lorelei",
        spotifyURI: "spotify:album:24cxezS5U9YTFapgKpYG16",
        artworkName: "24cxezS5U9YTFapgKpYG16"
    ))
    #expect(artwork == Data("jpeg".utf8))
}

@Test func fetchingWithNothingPlayingThrows() async {
    let fetcher = CurrentAlbumFetcher(nowPlaying: { "" }, http: fakeHTTP([:]))
    await #expect(throws: CurrentAlbumError.nothingPlaying) { try await fetcher.fetch() }
}

@Test func fetchingWhenThePageHasNoAlbumThrows() async {
    let fetcher = CurrentAlbumFetcher(
        nowPlaying: { playingOutput },
        http: fakeHTTP(["https://open.spotify.com/track/2504XYM0mWWPEVMD3XlLje": Data("<html></html>".utf8)])
    )
    await #expect(throws: CurrentAlbumError.albumNotFound) { try await fetcher.fetch() }
}
