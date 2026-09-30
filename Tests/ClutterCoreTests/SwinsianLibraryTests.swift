import Foundation
import Testing
@testable import ClutterCore

private func makeStore() -> SwinsianLibrary {
    SwinsianLibrary(fileURL: temporaryDirectory().appending(path: "swinsian.json"))
}

private let hejira = SwinsianAlbum.album(title: "Hejira", artist: "Joni Mitchell")
private let rust = SwinsianAlbum.album(title: "Rust Never Sleeps", artist: "Neil Young")

@Test func aSwinsianAlbumIsNamedByItsArtistAndTitle() {
    #expect(hejira.title == "Hejira")
    #expect(hejira.artist == "Joni Mitchell")
    #expect(hejira.uri.hasPrefix("swinsian:album:"))
    #expect(hejira.uri == SwinsianAlbum.album(title: "Hejira", artist: "Joni Mitchell").uri)
    #expect(hejira.uri != SwinsianAlbum.album(title: "Hejira", artist: "Neil Young").uri)
    #expect(hejira.uri != rust.uri)
}

@Test func aSwinsianAlbumsArtworkNameIsASafeFileName() {
    let odd = SwinsianAlbum.album(title: "AC/DC: Live?", artist: "Who / \"Me\"")
    #expect(odd.artworkName.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
}

@Test func recognizesSwinsianURIs() {
    #expect(SwinsianAlbum.isSwinsian(hejira))
    #expect(!SwinsianAlbum.isSwinsian(Album(title: "T", artist: "A", uri: "spotify:album:t", artworkName: "t")))
}

@Test func anEmptySwinsianLibraryHasNoAlbums() {
    #expect(makeStore().albums().isEmpty)
}

@Test func addedAlbumsComeBackNewestFirstAndPersist() {
    let store = makeStore()
    store.add(hejira, at: Date(timeIntervalSince1970: 100))
    store.add(rust, at: Date(timeIntervalSince1970: 200))
    let reloaded = SwinsianLibrary(fileURL: store.fileURL)
    #expect(reloaded.albums().map(\.album) == [rust, hejira])
    #expect(reloaded.albums().map(\.addedAt) == [Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 100)])
    #expect(reloaded.albums().allSatisfy { $0.artworkURL == nil })
}

@Test func addingAnAlbumAgainMakesItTheNewest() {
    let store = makeStore()
    store.add(hejira, at: Date(timeIntervalSince1970: 100))
    store.add(rust, at: Date(timeIntervalSince1970: 200))
    store.add(hejira, at: Date(timeIntervalSince1970: 300))
    #expect(store.albums().map(\.album) == [hejira, rust])
}

@Test func removingAnAlbumDropsIt() {
    let store = makeStore()
    store.add(hejira, at: Date(timeIntervalSince1970: 100))
    store.add(rust, at: Date(timeIntervalSince1970: 200))
    store.remove(uri: rust.uri)
    #expect(SwinsianLibrary(fileURL: store.fileURL).albums().map(\.album) == [hejira])
}

@Test func anUnreadableSwinsianLibraryHasNoAlbums() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: store.fileURL)
    #expect(store.albums().isEmpty)
}
