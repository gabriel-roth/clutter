import AppKit
import Testing
@testable import ClutterCore

private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

private func makeStore() -> LibraryStore {
    LibraryStore(fileURL: temporaryDirectory().appending(path: "library.json"))
}

@MainActor
private func makeController(
    store: LibraryStore,
    artwork: ArtworkStore = ArtworkStore(directory: temporaryDirectory()),
    player: SpotifyPlayer = SpyPlayer()
) -> ClutterController {
    ClutterController(store: store, artwork: artwork, player: player, screens: [screen], rng: SeededGenerator(seed: 3))
}

private func coverFrame(at origin: CGPoint) -> CGRect {
    CGRect(origin: origin, size: CGSize(width: ClutterController.windowSize, height: ClutterController.windowSize))
}

private let custom = Album(title: "Custom", artist: "Someone", spotifyURI: "spotify:album:custom1", artworkName: "custom1")

@MainActor @Test func firstLaunchScattersTheStarterAlbumsAndSavesThem() {
    let store = makeStore()
    let controller = makeController(store: store)
    #expect(controller.windows.map(\.album) == Album.starters)
    for window in controller.windows {
        #expect(screen.contains(window.frame), "\(window.frame) is off screen")
    }
    #expect(Set(controller.windows.map(\.frame.origin.x)).count == 6)
    #expect(store.load() == controller.library)
}

@MainActor @Test func unreadableLibraryFallsBackToStarters() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: store.fileURL)
    #expect(makeController(store: store).windows.map(\.album) == Album.starters)
}

@MainActor @Test func restoresASavedLibraryWithItsPositions() {
    let store = makeStore()
    store.save(Library(entries: [
        .init(album: Album.starters[4], origin: CGPoint(x: 100, y: 300)),
        .init(album: custom, origin: CGPoint(x: 700, y: 200)),
    ]))
    let controller = makeController(store: store)
    #expect(controller.windows.map(\.album) == [Album.starters[4], custom])
    #expect(controller.windows.map(\.frame) == [coverFrame(at: CGPoint(x: 100, y: 300)), coverFrame(at: CGPoint(x: 700, y: 200))])
}

@MainActor @Test func rePlacesCoversThatAreOffScreen() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: custom, origin: CGPoint(x: 5000, y: 5000))]))
    let controller = makeController(store: store)
    #expect(screen.contains(controller.windows[0].frame))
    #expect(store.load()?.entries[0].origin == controller.windows[0].frame.origin)
}

@MainActor @Test func movingAWindowSavesItsPosition() {
    let store = makeStore()
    let controller = makeController(store: store)
    controller.windows[2].setFrameOrigin(CGPoint(x: 321, y: 432))
    #expect(store.load()?.entries[2].origin == CGPoint(x: 321, y: 432))
}

@MainActor @Test func closingACoverRemovesItsAlbum() {
    let store = makeStore()
    let controller = makeController(store: store)
    let window = controller.windows[1]
    window.albumView.onClose?()
    #expect(!controller.windows.contains { $0 === window })
    #expect(!window.isVisible)
    #expect(store.load()?.contains(spotifyURI: Album.starters[1].spotifyURI) == false)
    #expect(store.load()?.entries.count == 5)
}

@MainActor @Test func removingEveryAlbumStaysEmptyAfterRelaunch() {
    let store = makeStore()
    let controller = makeController(store: store)
    for window in controller.windows { window.albumView.onClose?() }
    #expect(makeController(store: store).windows.isEmpty)
}

@MainActor @Test func doubleClickingAWindowPlaysItsAlbum() {
    let player = SpyPlayer()
    let controller = makeController(store: makeStore(), player: player)
    controller.windows[3].albumView.onDoubleClick?()
    #expect(player.played == [Album.starters[3]])
}

@MainActor @Test func windowsShowSavedArtwork() throws {
    let store = makeStore()
    store.save(Library(entries: [.init(album: custom, origin: CGPoint(x: 100, y: 100))]))
    let artwork = ArtworkStore(directory: temporaryDirectory())
    try artwork.save(jpegData(), for: custom)
    let controller = makeController(store: store, artwork: artwork)
    #expect(controller.windows[0].albumView.image != nil)
}

@MainActor @Test func addingANewAlbumShowsAndSavesIt() {
    let store = makeStore()
    let controller = makeController(store: store)
    #expect(controller.add(custom))
    #expect(controller.windows.last?.album == custom)
    #expect(screen.contains(controller.windows.last!.frame))
    #expect(store.load()?.contains(spotifyURI: custom.spotifyURI) == true)
}

@MainActor @Test func addingAnAlbumAlreadyShownChangesNothing() {
    let store = makeStore()
    let controller = makeController(store: store)
    #expect(!controller.add(Album.starters[0]))
    #expect(controller.windows.count == 6)
    #expect(store.load()?.entries.count == 6)
}
