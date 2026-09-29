import Foundation
import Testing
@testable import ClutterCore

private func makeLibrary(_ http: FakeHTTP, sleeps: Box<[Duration]> = Box([])) -> SpotifyLibrary {
    SpotifyLibrary(accessToken: { "TOKEN" }, http: { try http.handle($0) }, sleep: { sleeps.value.append($0) })
}

/// One `items` entry of GET /me/albums, trimmed to the fields Clutter reads plus a few it ignores.
private func item(_ id: String, addedAt: String, artists: [String] = ["Artist"], images: String? = nil) -> String {
    let artistJSON = artists.map { #"{"name":"\#($0)","id":"x"}"# }.joined(separator: ",")
    let imageJSON = images ?? #"[{"url":"https://i.scdn.co/image/\#(id)-640","height":640,"width":640},{"url":"https://i.scdn.co/image/\#(id)-300","height":300,"width":300}]"#
    return #"{"added_at":"\#(addedAt)","album":{"id":"\#(id)","name":"Title \#(id)","uri":"spotify:album:\#(id)","album_type":"album","artists":[\#(artistJSON)],"images":\#(imageJSON)}}"#
}

private func page(_ items: [String], next: String? = nil) -> String {
    let nextJSON = next.map { #""\#($0)""# } ?? "null"
    return #"{"href":"x","items":[\#(items.joined(separator: ","))],"limit":50,"next":\#(nextJSON),"offset":0,"total":999}"#
}

@Test func recentAlbumsAsksForTheFirstNWithTheAccessToken() async throws {
    let http = FakeHTTP([(200, page([item("a", addedAt: "2026-09-27T18:04:12Z")]))])
    let albums = try await makeLibrary(http).recentAlbums(count: 10)
    let request = http.recorded[0]
    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://api.spotify.com/v1/me/albums?limit=10&offset=0")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer TOKEN")
    #expect(albums == [SavedAlbum(
        album: Album(title: "Title a", artist: "Artist", spotifyURI: "spotify:album:a", artworkName: "a"),
        addedAt: Date(timeIntervalSince1970: 1_790_532_252),
        artworkURL: URL(string: "https://i.scdn.co/image/a-640")
    )])
}

@Test func recentAlbumsPagesInFifties() async throws {
    let first = (0..<50).map { item("p\($0)", addedAt: "2026-09-01T00:00:00Z") }
    let second = (0..<50).map { item("q\($0)", addedAt: "2026-08-01T00:00:00Z") }
    let http = FakeHTTP([(200, page(first, next: "more")), (200, page(second, next: "more"))])
    let albums = try await makeLibrary(http).recentAlbums(count: 100)
    #expect(albums.count == 100)
    #expect(http.recorded.map(\.url?.absoluteString) == [
        "https://api.spotify.com/v1/me/albums?limit=50&offset=0",
        "https://api.spotify.com/v1/me/albums?limit=50&offset=50",
    ])
}

@Test func recentAlbumsStopsWhenTheLibraryRunsOut() async throws {
    // Asking for 100 from a 3-album library: one request, then stop (FakeHTTP would throw on a second).
    let http = FakeHTTP([(200, page([item("a", addedAt: "2026-09-03T00:00:00Z"), item("b", addedAt: "2026-09-02T00:00:00Z"), item("c", addedAt: "2026-09-01T00:00:00Z")]))])
    let albums = try await makeLibrary(http).recentAlbums(count: 100)
    #expect(albums.map(\.album.artworkName) == ["a", "b", "c"])
    #expect(http.recorded.count == 1)
}

@Test func recentAlbumsAreSortedNewestFirst() async throws {
    let http = FakeHTTP([(200, page([item("old", addedAt: "2020-01-01T00:00:00Z"), item("new", addedAt: "2026-01-01T00:00:00Z")]))])
    let albums = try await makeLibrary(http).recentAlbums(count: 2)
    #expect(albums.map(\.album.artworkName) == ["new", "old"])
}

@Test func artistsAreJoinedAndFractionalSecondsAreRead() async throws {
    let http = FakeHTTP([(200, page([item("a", addedAt: "2026-09-27T18:04:12.500Z", artists: ["One", "Two"])]))])
    let album = try await makeLibrary(http).recentAlbums(count: 1)[0]
    #expect(album.album.artist == "One, Two")
    #expect(album.addedAt == Date(timeIntervalSince1970: 1_790_532_252.5))
}

@Test func albumWithoutUsableImagesStillComesBack() async throws {
    let http = FakeHTTP([(200, page([
        item("none", addedAt: "2026-09-02T00:00:00Z", images: "[]"),
        item("nulls", addedAt: "2026-09-01T00:00:00Z", images: #"[{"url":"https://i.scdn.co/image/n","height":null,"width":null}]"#),
    ]))])
    let albums = try await makeLibrary(http).recentAlbums(count: 2)
    #expect(albums.map(\.artworkURL) == [nil, URL(string: "https://i.scdn.co/image/n")])
}

@Test func failedRequestThrowsWithStatusAndBody() async {
    let http = FakeHTTP([(401, #"{"error":{"status":401,"message":"The access token expired"}}"#)])
    await #expect(throws: SpotifyLibraryError.requestFailed(status: 401, body: #"{"error":{"status":401,"message":"The access token expired"}}"#)) {
        try await makeLibrary(http).recentAlbums(count: 10)
    }
}

@Test func unreadableReplyIsMalformed() async {
    let http = FakeHTTP([(200, "<html>")])
    await #expect(throws: SpotifyLibraryError.malformedResponse) { try await makeLibrary(http).recentAlbums(count: 10) }
}

@Test func containsChecksOneAlbumURI() async throws {
    let http = FakeHTTP([(200, "[true]")])
    #expect(try await makeLibrary(http).contains(albumURI: "spotify:album:abc"))
    #expect(http.recorded[0].httpMethod == "GET")
    #expect(http.recorded[0].url?.absoluteString == "https://api.spotify.com/v1/me/library/contains?uris=spotify%3Aalbum%3Aabc")
}

@Test func saveAndRemoveUseTheLibraryEndpoint() async throws {
    let http = FakeHTTP([(200, ""), (200, "")])
    let library = makeLibrary(http)
    try await library.save(albumURI: "spotify:album:abc")
    try await library.remove(albumURI: "spotify:album:abc")
    #expect(http.recorded.map(\.httpMethod) == ["PUT", "DELETE"])
    #expect(http.recorded.map(\.url?.absoluteString) == Array(repeating: "https://api.spotify.com/v1/me/library?uris=spotify%3Aalbum%3Aabc", count: 2))
    #expect(http.recorded.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer TOKEN" })
}

@Test func bumpingASavedAlbumRemovesThenSavesIt() async throws {
    let http = FakeHTTP([(200, "[true]"), (200, ""), (200, "")])
    try await makeLibrary(http).bumpToMostRecent(albumURI: "spotify:album:abc")
    #expect(http.recorded.map(\.httpMethod) == ["GET", "DELETE", "PUT"])
}

@Test func bumpingAnUnsavedAlbumJustSavesIt() async throws {
    let http = FakeHTTP([(200, "[false]"), (200, "")])
    try await makeLibrary(http).bumpToMostRecent(albumURI: "spotify:album:abc")
    #expect(http.recorded.map(\.httpMethod) == ["GET", "PUT"])
}

@Test func reSavingAfterARemoveRetriesAFailedSaveAfterASecond() async throws {
    let http = FakeHTTP([(200, "[true]"), (200, ""), (500, "oops"), (200, "")])
    let sleeps = Box<[Duration]>([])
    try await makeLibrary(http, sleeps: sleeps).bumpToMostRecent(albumURI: "spotify:album:abc")
    #expect(http.recorded.map(\.httpMethod) == ["GET", "DELETE", "PUT", "PUT"])
    #expect(sleeps.value == [.seconds(1)])
}

@Test func reSavingWaitsAsLongAsARateLimitAsks() async throws {
    let http = FakeHTTP(withHeaders: [(200, "[true]", [:]), (200, "", [:]), (429, "", ["Retry-After": "3"]), (200, "", [:])])
    let sleeps = Box<[Duration]>([])
    try await makeLibrary(http, sleeps: sleeps).bumpToMostRecent(albumURI: "spotify:album:abc")
    #expect(sleeps.value == [.seconds(3)])
}

@Test func reSavingCapsARateLimitWaitAndDefaultsAMissingOne() async throws {
    let http = FakeHTTP(withHeaders: [(200, "[true]", [:]), (200, "", [:]), (429, "", ["Retry-After": "3600"]), (429, "", [:]), (200, "", [:])])
    let sleeps = Box<[Duration]>([])
    try await makeLibrary(http, sleeps: sleeps).bumpToMostRecent(albumURI: "spotify:album:abc")
    #expect(sleeps.value == [.seconds(10), .seconds(1)])
}

@Test func reSavingGivesUpAfterThreeTries() async {
    let http = FakeHTTP([(200, "[true]"), (200, ""), (500, ""), (500, ""), (500, "")])
    let sleeps = Box<[Duration]>([])
    await #expect(throws: SpotifyLibraryError.removedButNotSaved(albumURI: "spotify:album:abc")) {
        try await makeLibrary(http, sleeps: sleeps).bumpToMostRecent(albumURI: "spotify:album:abc")
    }
    #expect(http.recorded.filter { $0.httpMethod == "PUT" }.count == 3)
    #expect(sleeps.value == [.seconds(1), .seconds(2)])
}

@Test func savingAnUnsavedAlbumDoesNotRetry() async {
    let http = FakeHTTP([(200, "[false]"), (500, "oops")])
    await #expect(throws: SpotifyLibraryError.requestFailed(status: 500, body: "oops")) {
        try await makeLibrary(http).bumpToMostRecent(albumURI: "spotify:album:abc")
    }
    #expect(http.recorded.map(\.httpMethod) == ["GET", "PUT"])
}

@Test func anUnreadableItemIsSkipped() async throws {
    let http = FakeHTTP([(200, page([#"{"added_at":"2026-09-02T00:00:00Z","album":null}"#, item("good", addedAt: "2026-09-01T00:00:00Z")]))])
    let albums = try await makeLibrary(http).recentAlbums(count: 10)
    #expect(albums.map(\.album.artworkName) == ["good"])
}

@Test func aSkippedItemStillCountsTowardPaging() async throws {
    // 49 good items and one bad one fill the first page, so the next request starts at 50.
    let first = [#"{"album":null}"#] + (0..<49).map { item("p\($0)", addedAt: "2026-09-01T00:00:00Z") }
    let second = (0..<50).map { item("q\($0)", addedAt: "2026-08-01T00:00:00Z") }
    let http = FakeHTTP([(200, page(first, next: "more")), (200, page(second, next: "more"))])
    let albums = try await makeLibrary(http).recentAlbums(count: 100)
    #expect(albums.count == 99)
    #expect(http.recorded.map(\.url?.absoluteString) == [
        "https://api.spotify.com/v1/me/albums?limit=50&offset=0",
        "https://api.spotify.com/v1/me/albums?limit=50&offset=50",
    ])
}

@Test func aPageWithoutItemsIsMalformed() async {
    let http = FakeHTTP([(200, #"{"next":null}"#)])
    await #expect(throws: SpotifyLibraryError.malformedResponse) { try await makeLibrary(http).recentAlbums(count: 10) }
}
