import Foundation
import Testing
@testable import ClutterCore

private let playingOutput = "spotify:track:2504XYM0mWWPEVMD3XlLje"

// Trimmed from the real page at https://open.spotify.com/track/2504XYM0mWWPEVMD3XlLje
private let trackHTML = #"<html><head><meta property="og:title" content="Watching Heaven Fall"/><meta property="og:description" content="This Is Lorelei · The Singer in My Band · Song · 2026"/><meta name="music:album" content="https://open.spotify.com/album/24cxezS5U9YTFapgKpYG16"/><meta name="music:album:track" content="4"/></head></html>"#

@Test func parsesAPlayingTrack() {
    #expect(NowPlaying.parse(playingOutput) == NowPlaying(trackURI: "spotify:track:2504XYM0mWWPEVMD3XlLje"))
    #expect(NowPlaying.parse(playingOutput)?.trackID == "2504XYM0mWWPEVMD3XlLje")
}

@Test(arguments: [
    "",                                         // Spotify not running or stopped
    "spotify:episode:abc",                      // podcast
    "spotify:ad:abc",                           // advert
    "spotify:local:Artist:Album:Song:180",      // local file
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

@Test func fetchesThePlayingAlbumsURI() async throws {
    let fetcher = CurrentAlbumFetcher(
        nowPlaying: { playingOutput },
        http: fakeHTTP(["https://open.spotify.com/track/2504XYM0mWWPEVMD3XlLje": Data(trackHTML.utf8)])
    )
    #expect(try await fetcher.fetchAlbumURI() == "spotify:album:24cxezS5U9YTFapgKpYG16")
}

@Test func fetchingWithNothingPlayingThrows() async {
    let fetcher = CurrentAlbumFetcher(nowPlaying: { "" }, http: fakeHTTP([:]))
    await #expect(throws: CurrentAlbumError.nothingPlaying) { try await fetcher.fetchAlbumURI() }
}

@Test func fetchingWhenThePageHasNoAlbumThrows() async {
    let fetcher = CurrentAlbumFetcher(
        nowPlaying: { playingOutput },
        http: fakeHTTP(["https://open.spotify.com/track/2504XYM0mWWPEVMD3XlLje": Data("<html></html>".utf8)])
    )
    await #expect(throws: CurrentAlbumError.albumNotFound) { try await fetcher.fetchAlbumURI() }
}
