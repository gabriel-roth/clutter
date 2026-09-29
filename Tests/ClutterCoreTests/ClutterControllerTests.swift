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

private func album(_ id: String, title: String? = nil) -> Album {
    Album(title: title ?? "Title \(id)", artist: "Artist", spotifyURI: "spotify:album:\(id)", artworkName: id)
}
private let a = album("a"), b = album("b"), c = album("c"), d = album("d")

@MainActor @Test func firstLaunchStartsEmpty() {
    let store = makeStore()
    #expect(makeController(store: store).windows.isEmpty)
}

@MainActor @Test func unreadableLibraryStartsEmpty() throws {
    let store = makeStore()
    try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: store.fileURL)
    #expect(makeController(store: store).windows.isEmpty)
}

@MainActor @Test func restoresASavedLibraryWithItsPositionsAndStackingOrder() {
    let store = makeStore()
    store.save(Library(entries: [
        .init(album: b, origin: CGPoint(x: 100, y: 300)),
        .init(album: a, origin: CGPoint(x: 700, y: 200)),
    ]))
    let controller = makeController(store: store)
    #expect(controller.windows.map(\.album) == [b, a])
    #expect(controller.windows.map(\.frame) == [coverFrame(at: CGPoint(x: 100, y: 300)), coverFrame(at: CGPoint(x: 700, y: 200))])
}

@MainActor @Test func rePlacesCoversThatAreOffScreen() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 5000, y: 5000))]))
    let controller = makeController(store: store)
    #expect(screen.contains(controller.windows[0].frame))
    #expect(store.load()?.entries[0].origin == controller.windows[0].frame.origin)
}

@MainActor @Test func movingAWindowSavesItsPosition() {
    let store = makeStore()
    store.save(Library(entries: [a, b, c].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) }))
    let controller = makeController(store: store)
    controller.windows[2].setFrameOrigin(CGPoint(x: 321, y: 432))
    #expect(store.load()?.entries[2].origin == CGPoint(x: 321, y: 432))
}

@MainActor @Test func doubleClickingAWindowPlaysItsAlbum() {
    let player = SpyPlayer()
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 100, y: 100))]))
    let controller = makeController(store: store, player: player)
    controller.windows[0].albumView.onDoubleClick?()
    #expect(player.played == [a])
}

@MainActor @Test func windowsShowSavedArtwork() throws {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 100, y: 100))]))
    let artwork = ArtworkStore(directory: temporaryDirectory())
    try artwork.save(jpegData(), for: a)
    #expect(makeController(store: store, artwork: artwork).windows[0].albumView.image != nil)
}

@MainActor @Test func applyShowsNewAlbumsOnScreenWithTheNewestFrontmost() {
    let store = makeStore()
    let controller = makeController(store: store)
    controller.apply([c, b, a])
    #expect(controller.windows.map(\.album) == [a, b, c])
    let allVisible = controller.windows.allSatisfy { $0.isVisible }
    #expect(allVisible)
    for window in controller.windows {
        #expect(screen.contains(window.frame), "\(window.frame) is off screen")
    }
    #expect(store.load() == controller.library)
}

@MainActor @Test func applyKeepsSurvivingCoversAndStacksNewOnesOnTop() {
    let store = makeStore()
    store.save(Library(entries: [
        .init(album: a, origin: CGPoint(x: 100, y: 300)),
        .init(album: b, origin: CGPoint(x: 700, y: 200)),
    ]))
    let controller = makeController(store: store)
    let (windowA, windowB) = (controller.windows[0], controller.windows[1])
    controller.apply([d, b, a])
    #expect(controller.windows.map(\.album) == [a, b, d])
    #expect(controller.windows[0] === windowA)
    #expect(controller.windows[1] === windowB)
    #expect(windowA.frame == coverFrame(at: CGPoint(x: 100, y: 300)))
    #expect(windowB.frame == coverFrame(at: CGPoint(x: 700, y: 200)))
    #expect(store.load()?.entries.map(\.album) == [a, b, d])
}

@MainActor @Test func applyClosesCoversWhoseAlbumsLeft() {
    let store = makeStore()
    store.save(Library(entries: [a, b].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) }))
    let controller = makeController(store: store)
    controller.showWindows()
    let windowA = controller.windows[0]
    controller.apply([b])
    #expect(controller.windows.map(\.album) == [b])
    #expect(!windowA.isVisible)
    #expect(store.load()?.entries.map(\.album) == [b])
}

@MainActor @Test func applyWithNoAlbumsEmptiesTheDesktop() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 100, y: 100))]))
    let controller = makeController(store: store)
    controller.apply([])
    #expect(controller.windows.isEmpty)
    #expect(store.load() == Library())
}

@MainActor @Test func applyRebuildsACoverWhoseDetailsChangedInPlace() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 100, y: 300))]))
    let controller = makeController(store: store)
    let renamed = album("a", title: "Renamed")
    controller.apply([renamed])
    #expect(controller.windows.map(\.album) == [renamed])
    #expect(controller.windows[0].frame == coverFrame(at: CGPoint(x: 100, y: 300)))
}

@MainActor @Test func clickingACoverBringsItToTheFrontAndSavesTheOrder() {
    let store = makeStore()
    store.save(Library(entries: [a, b, c].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) }))
    let controller = makeController(store: store)
    controller.windows[0].albumView.onMouseDown?()
    #expect(controller.windows.map(\.album) == [b, c, a])
    #expect(store.load()?.entries.map(\.album) == [b, c, a])
}

@MainActor @Test func clickingTheFrontmostCoverChangesNothing() {
    let store = makeStore()
    let saved = Library(entries: [a, b, c].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) })
    store.save(saved)
    let controller = makeController(store: store)
    controller.windows[2].albumView.onMouseDown?()
    #expect(controller.windows.map(\.album) == [a, b, c])
    #expect(store.load() == saved)
}

@MainActor @Test func bringToFrontMovesThatCoverToTheTop() {
    let store = makeStore()
    store.save(Library(entries: [a, b, c].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) }))
    let controller = makeController(store: store)
    controller.bringToFront(spotifyURI: b.spotifyURI)
    #expect(controller.windows.map(\.album) == [a, c, b])
    #expect(store.load()?.entries.map(\.album) == [a, c, b])
    controller.bringToFront(spotifyURI: d.spotifyURI)
    #expect(controller.windows.map(\.album) == [a, c, b])
}

@MainActor @Test func coversOpenAtTheChosenSize() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 100, y: 300))]))
    let controller = makeController(store: store, coverSize: .large)
    #expect(controller.windows[0].frame == coverFrame(at: CGPoint(x: 100, y: 300), size: .large))
}

@MainActor @Test func changingTheSizeResizesCoversInPlaceFromTheTopLeft() {
    let store = makeStore()
    store.save(Library(entries: [
        .init(album: a, origin: CGPoint(x: 100, y: 300)),
        .init(album: b, origin: CGPoint(x: 700, y: 200)),
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

@MainActor @Test func coversAddedAfterAResizeUseTheNewSizeAndStayOnScreen() {
    let controller = makeController(store: makeStore())
    controller.setCoverSize(.large)
    controller.apply([a, b, c])
    for window in controller.windows {
        #expect(window.frame.size == CGSize(width: 300, height: 300))
        #expect(screen.contains(window.frame), "\(window.frame) is off screen")
    }
}
