import AppKit
import Testing
@testable import ClutterCore

@Test func missingLibraryFileLoadsAsNil() {
    let store = LibraryStore(fileURL: temporaryDirectory().appending(path: "library.json"))
    #expect(store.load() == nil)
}

@Test func savedLibraryLoadsBackEqualAndCreatesTheDirectory() {
    let store = LibraryStore(fileURL: temporaryDirectory().appending(path: "nested/library.json"))
    var library = Library()
    library.add(Album.starters[2], at: CGPoint(x: 100, y: 200))
    store.save(library)
    #expect(store.load() == library)
}

@Test func emptyLibraryLoadsAsEmptyNotNil() {
    let store = LibraryStore(fileURL: temporaryDirectory().appending(path: "library.json"))
    store.save(Library())
    #expect(store.load() == Library())
}

@Test func unreadableFileLoadsAsNil() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "library.json")
    try Data("not json".utf8).write(to: file)
    #expect(LibraryStore(fileURL: file).load() == nil)
}

@Test func defaultDirectoryIsClutterInApplicationSupport() {
    #expect(LibraryStore.defaultDirectory.lastPathComponent == "Clutter")
    #expect(LibraryStore.defaultDirectory.deletingLastPathComponent() == URL.applicationSupportDirectory)
}

@Test func savedArtworkLoadsFromTheDirectory() throws {
    let store = ArtworkStore(directory: temporaryDirectory())
    let album = Album(title: "T", artist: "A", spotifyURI: "spotify:album:abc", artworkName: "abc")
    try store.save(jpegData(), for: album)
    #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "abc.jpg").path))
    #expect(store.image(for: album)?.size == CGSize(width: 4, height: 4))
}

@Test func missingArtworkIsNil() {
    let store = ArtworkStore(directory: temporaryDirectory())
    let album = Album(title: "T", artist: "A", spotifyURI: "spotify:album:nope", artworkName: "nope")
    #expect(store.image(for: album) == nil)
}
