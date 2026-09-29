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
    player: SpotifyPlayer = SpyPlayer(),
    coverSize: CoverSize = .medium
) -> ClutterController {
    ClutterController(store: store, artwork: artwork, player: player, screens: [screen], coverSize: coverSize, rng: SeededGenerator(seed: 3))
}

private func coverFrame(at origin: CGPoint, size: CoverSize = .medium) -> CGRect {
    CGRect(origin: origin, size: CGSize(width: size.points, height: size.points))
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

@MainActor @Test func closedCoverWindowIsKeptAliveUntilTheCurrentEventFinishes() async {
    let controller = makeController(store: makeStore())
    let window = controller.windows[0]
    window.albumView.onClose?()
    // The close button's action is still running when this returns, so its window must not be released yet.
    #expect(controller.closingWindows == [window])
    try? await Task.sleep(for: .milliseconds(50))
    #expect(controller.closingWindows.isEmpty)
}

@MainActor @Test func coversOpenAtTheChosenSize() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: custom, origin: CGPoint(x: 100, y: 300))]))
    let controller = makeController(store: store, coverSize: .large)
    #expect(controller.windows[0].frame == coverFrame(at: CGPoint(x: 100, y: 300), size: .large))
}

@MainActor @Test func firstLaunchKeepsLargeCoversOnScreen() {
    let controller = makeController(store: makeStore(), coverSize: .large)
    for window in controller.windows {
        #expect(window.frame.size == CGSize(width: 300, height: 300))
        #expect(screen.contains(window.frame), "\(window.frame) is off screen")
    }
}

@MainActor @Test func changingTheSizeResizesCoversInPlaceFromTheTopLeft() {
    let store = makeStore()
    store.save(Library(entries: [
        .init(album: custom, origin: CGPoint(x: 100, y: 300)),
        .init(album: Album.starters[0], origin: CGPoint(x: 700, y: 200)),
    ]))
    let controller = makeController(store: store)
    controller.setCoverSize(.small)
    // Top-left corners stay put: y moves up by the 60-point difference in height.
    #expect(controller.windows.map(\.frame) == [
        coverFrame(at: CGPoint(x: 100, y: 360), size: .small),
        coverFrame(at: CGPoint(x: 700, y: 260), size: .small),
    ])
    #expect(store.load()?.entries.map(\.origin) == [CGPoint(x: 100, y: 360), CGPoint(x: 700, y: 260)])
    #expect(controller.coverSize == .small)
}

@MainActor @Test func coversAddedAfterAResizeUseTheNewSize() {
    let controller = makeController(store: makeStore())
    controller.setCoverSize(.large)
    controller.add(custom)
    #expect(controller.windows.last?.frame.size == CGSize(width: 300, height: 300))
    #expect(screen.contains(controller.windows.last!.frame))
}
