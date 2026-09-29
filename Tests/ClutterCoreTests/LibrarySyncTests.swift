import AppKit
import Testing
@testable import ClutterCore

private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

private func item(_ id: String, addedAt: String) -> String {
    #"{"added_at":"\#(addedAt)","album":{"id":"\#(id)","name":"Title \#(id)","uri":"spotify:album:\#(id)","artists":[{"name":"Artist"}],"images":[{"url":"https://i.scdn.co/image/\#(id)","width":640,"height":640}]}}"#
}

private func page(_ items: [String]) -> String {
    #"{"items":[\#(items.joined(separator: ","))],"next":null}"#
}

@MainActor
private struct Harness {
    let store = LibraryStore(fileURL: temporaryDirectory().appending(path: "library.json"))
    let artwork = ArtworkStore(directory: temporaryDirectory())
    let downloads = Box<[URL]>([])
    let controller: ClutterController
    let http: FakeHTTP

    init(replies: [(status: Int, body: String)], saved: Library? = nil) {
        if let saved { store.save(saved) }
        http = FakeHTTP(replies)
        controller = ClutterController(store: store, artwork: artwork, player: SpyPlayer(), screens: [screen], rng: SeededGenerator(seed: 1))
    }

    func sync(count: Int = 10, failDownloads: Bool = false) -> LibrarySync {
        let http = http, downloads = downloads
        return LibrarySync(
            library: SpotifyLibrary(accessToken: { "TOKEN" }, http: { try http.handle($0) }),
            artwork: artwork,
            controller: controller,
            albumCount: { count },
            download: { url in
                downloads.value.append(url)
                if failDownloads { throw URLError(.notConnectedToInternet) }
                return jpegData()
            }
        )
    }
}

private func album(_ id: String) -> Album {
    Album(title: "Title \(id)", artist: "Artist", spotifyURI: "spotify:album:\(id)", artworkName: id)
}

@MainActor @Test func refreshShowsTheFetchedAlbumsWithArtwork() async {
    let harness = Harness(replies: [(200, page([item("new", addedAt: "2026-09-02T00:00:00Z"), item("old", addedAt: "2026-09-01T00:00:00Z")]))])
    await harness.sync(count: 2).refresh().value
    #expect(harness.controller.windows.map(\.album.artworkName) == ["old", "new"])
    #expect(harness.controller.windows.allSatisfy { $0.albumView.image != nil })
    #expect(harness.http.recorded[0].url?.absoluteString == "https://api.spotify.com/v1/me/albums?limit=2&offset=0")
}

@MainActor @Test func refreshDownloadsOnlyMissingArtworkAndPrunesTheRest() async throws {
    let harness = Harness(replies: [(200, page([item("have", addedAt: "2026-09-02T00:00:00Z"), item("need", addedAt: "2026-09-01T00:00:00Z")]))])
    try harness.artwork.save(jpegData(), for: album("have"))
    try harness.artwork.save(jpegData(), for: album("gone"))
    await harness.sync().refresh().value
    #expect(harness.downloads.value == [URL(string: "https://i.scdn.co/image/need")!])
    #expect(!harness.artwork.hasImage(for: album("gone")))
    #expect(harness.artwork.hasImage(for: album("have")))
    #expect(harness.artwork.hasImage(for: album("need")))
}

@MainActor @Test func failedArtworkDownloadStillShowsTheAlbum() async {
    let harness = Harness(replies: [(200, page([item("a", addedAt: "2026-09-01T00:00:00Z")]))])
    await harness.sync(failDownloads: true).refresh().value
    #expect(harness.controller.windows.map(\.album.artworkName) == ["a"])
    #expect(harness.controller.windows[0].albumView.image == nil)
}

@MainActor @Test func aPlaceholderCoverPicksUpArtworkOnALaterRefresh() async {
    let reply = (status: 200, body: page([item("a", addedAt: "2026-09-01T00:00:00Z")]))
    let harness = Harness(replies: [reply, reply])
    await harness.sync(failDownloads: true).refresh().value
    let window = harness.controller.windows[0]
    #expect(window.albumView.image == nil)
    await harness.sync().refresh().value
    #expect(harness.controller.windows[0] === window)
    #expect(window.albumView.image != nil)
}

@MainActor @Test(arguments: [401, 500])
func failedFetchLeavesTheDesktopAlone(status: Int) async {
    let saved = Library(entries: [.init(album: album("kept"), origin: CGPoint(x: 100, y: 100))])
    let harness = Harness(replies: [(status, "{}")], saved: saved)
    await harness.sync().refresh().value
    #expect(harness.controller.windows.map(\.album.artworkName) == ["kept"])
    #expect(harness.store.load() == saved)
}

@MainActor @Test func networkErrorLeavesTheDesktopAlone() async {
    let saved = Library(entries: [.init(album: album("kept"), origin: CGPoint(x: 100, y: 100))])
    let harness = Harness(replies: [], saved: saved)  // FakeHTTP throws when it has no replies.
    await harness.sync().refresh().value
    #expect(harness.controller.windows.map(\.album.artworkName) == ["kept"])
}

/// Blocks waiters until opened. Ignores cancellation, so a cancelled waiter stays blocked too.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if !isOpen { waiters.append(continuation) }
                return isOpen
            }
            if resumeNow { continuation.resume() }
        }
    }

    func open() {
        let waiting = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }
}

@MainActor @Test func aNewRefreshCancelsTheOneRunning() async {
    let harness = Harness(replies: [
        (200, page([item("first", addedAt: "2026-09-01T00:00:00Z")])),
        (200, page([item("second", addedAt: "2026-09-01T00:00:00Z")])),
    ])
    // The first refresh stalls downloading its cover until the second has finished.
    let firstDownloading = Gate(), releaseFirst = Gate()
    let http = harness.http
    let sync = LibrarySync(
        library: SpotifyLibrary(accessToken: { "TOKEN" }, http: { try http.handle($0) }),
        artwork: harness.artwork,
        controller: harness.controller,
        albumCount: { 10 },
        download: { url in
            if url.lastPathComponent == "first" {
                firstDownloading.open()
                await releaseFirst.wait()
            }
            return jpegData()
        }
    )
    let first = sync.refresh()
    await firstDownloading.wait()
    let second = sync.refresh()
    await second.value
    releaseFirst.open()
    await first.value
    #expect(first.isCancelled)
    #expect(harness.controller.windows.map(\.album.artworkName) == ["second"])
}
