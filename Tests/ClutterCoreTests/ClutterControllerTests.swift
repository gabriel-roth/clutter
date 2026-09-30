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
    player: AlbumPlayer = SpyPlayer(),
    coverSize: CoverSize = .medium
) -> ClutterController {
    ClutterController(store: store, artwork: artwork, player: player, screens: [screen], coverSize: coverSize, rng: SeededGenerator(seed: 3))
}

private func coverFrame(at origin: CGPoint, size: CoverSize = .medium) -> CGRect {
    CGRect(origin: origin, size: CGSize(width: size.points, height: size.points))
}

private func album(_ id: String, title: String? = nil) -> Album {
    Album(title: title ?? "Title \(id)", artist: "Artist", uri: "spotify:album:\(id)", artworkName: id)
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
    #expect(store.load()?.entries[0].origin == controller.windows[0].coverFrame.origin)
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
    controller.bringToFront(uri: b.uri)
    #expect(controller.windows.map(\.album) == [a, c, b])
    #expect(store.load()?.entries.map(\.album) == [a, c, b])
    controller.bringToFront(uri: d.uri)
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
        #expect(window.coverFrame.size == CGSize(width: 300, height: 300))
        #expect(screen.contains(window.frame), "\(window.frame) is off screen")
    }
}

@MainActor @Test func dropsLegacyStarterAlbumsAndSavesWithoutThem() {
    let store = makeStore()
    let legacy = Album(title: "Hovvdy", artist: "Hovvdy", uri: "spotify:album:1jEwzUBvIlVPeOfqR3Ghr0", artworkName: "hovvdy")
    store.save(Library(entries: [
        .init(album: legacy, origin: CGPoint(x: 100, y: 300)),
        .init(album: a, origin: CGPoint(x: 700, y: 200)),
    ]))
    let controller = makeController(store: store)
    #expect(controller.windows.map(\.album) == [a])
    #expect(store.load() == Library(entries: [.init(album: a, origin: CGPoint(x: 700, y: 200))]))
}

@MainActor @Test func applyOrdersFrontOnlyNewCoversAndLeavesTheRestWhereTheyAre() {
    let store = makeStore()
    store.save(Library(entries: [a, b].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) }))
    let controller = makeController(store: store)
    controller.showWindows()
    let (windowA, windowB) = (controller.windows[0], controller.windows[1])
    windowA.orderFrontRegardless()  // Out of step with the saved order, as if another app's window came between.
    controller.apply([d, c, b, a])
    let (windowC, windowD) = (controller.windows[2], controller.windows[3])
    #expect(windowC.isVisible && windowD.isVisible)
    // Front to back: the new covers, newest first, then the old ones in the order they were left in.
    let order = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue)
    let ours = [windowD, windowC, windowA, windowB].map(\.windowNumber)
    #expect(order.filter(ours.contains) == ours)
    controller.apply([])
}

@MainActor @Test func hoverInfoSettingReachesEveryCoverIncludingNewOnes() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 100, y: 300))]))
    let controller = ClutterController(store: store, artwork: ArtworkStore(directory: temporaryDirectory()), player: SpyPlayer(), screens: [screen], showsInfoOnHover: false, rng: SeededGenerator(seed: 3))
    #expect(controller.windows.allSatisfy { !$0.albumView.showsInfoOnHover })
    controller.setShowsInfoOnHover(true)
    controller.apply([b, a])
    #expect(controller.windows.count == 2)
    #expect(controller.windows.allSatisfy { $0.albumView.showsInfoOnHover })
    controller.setShowsInfoOnHover(false)
    #expect(controller.windows.allSatisfy { !$0.albumView.showsInfoOnHover })
}

@MainActor @Test func removingACoverClosesItSavesTheLibraryAndReportsTheAlbum() {
    let store = makeStore()
    store.save(Library(entries: [a, b].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) }))
    let controller = makeController(store: store)
    controller.showWindows()
    var removed: [Album] = []
    controller.onRemoveAlbum = { removed.append($0) }
    let windowA = controller.windows[0]
    windowA.albumView.onRemove?()
    #expect(removed == [a])
    #expect(controller.windows.map(\.album) == [b])
    #expect(!windowA.isVisible)
    #expect(store.load()?.entries.map(\.album) == [b])
}

@MainActor @Test func aCoverBeingRemovedStaysOffTheDesktopUntilTheRemovalFinishes() {
    let store = makeStore()
    store.save(Library(entries: [a, b].map { .init(album: $0, origin: CGPoint(x: 100, y: 100)) }))
    let controller = makeController(store: store)
    controller.windows[0].albumView.onRemove?()
    controller.apply([b, a])
    #expect(controller.windows.map(\.album) == [b])
    controller.finishRemoving(uri: a.uri)
    controller.apply([b, a])
    #expect(controller.windows.map(\.album) == [b, a])
}

@MainActor @Test func hidingTakesEveryCoverOffTheDesktopAndShowingBringsThemBack() {
    let controller = makeController(store: makeStore())
    controller.apply([a, b])
    controller.setHidden(true)
    #expect(controller.isHidden)
    #expect(controller.windows.allSatisfy { !$0.isVisible })
    controller.setHidden(false)
    #expect(!controller.isHidden)
    #expect(controller.windows.allSatisfy { $0.isVisible })
}

@MainActor @Test func coversAppliedWhileHiddenStayHiddenUntilShown() {
    let controller = makeController(store: makeStore())
    controller.setHidden(true)
    controller.apply([a])
    #expect(!controller.windows[0].isVisible)
    controller.setHidden(false)
    #expect(controller.windows[0].isVisible)
}

@MainActor @Test func bringingACoverToTheFrontShowsHiddenCovers() {
    let controller = makeController(store: makeStore())
    controller.apply([a, b])
    controller.setHidden(true)
    controller.bringToFront(uri: a.uri)
    #expect(!controller.isHidden)
    #expect(controller.windows.allSatisfy { $0.isVisible })
}

@MainActor @Test func toggleBringsCoversForwardWhenTheyAreShowingBehindOtherWindows() {
    let controller = makeController(store: makeStore())
    controller.apply([a, b])
    controller.coversAreInFront = { false }
    controller.toggle()
    #expect(!controller.isHidden)
    #expect(controller.windows.allSatisfy { $0.isVisible })
}

@MainActor @Test func toggleActivatesTheAppOnlyWhenItShowsCovers() {
    let controller = makeController(store: makeStore())
    controller.apply([a, b])
    var activations = 0
    controller.onShownByToggle = { activations += 1 }
    controller.coversAreInFront = { false }
    controller.toggle()
    #expect(activations == 1)
    controller.coversAreInFront = { true }
    controller.toggle()
    #expect(controller.isHidden)
    #expect(activations == 1)
    controller.toggle()
    #expect(activations == 2)
}

@MainActor @Test func toggleHidesCoversThatAreInFrontAndShowsHiddenOnes() {
    let controller = makeController(store: makeStore())
    controller.apply([a, b])
    controller.coversAreInFront = { true }
    controller.toggle()
    #expect(controller.isHidden)
    controller.coversAreInFront = { false }
    controller.toggle()
    #expect(!controller.isHidden)
}

@MainActor @Test func tidyLinesCoversUpInAnEvenGridNearWhereTheyWere() {
    let store = makeStore()
    store.save(Library(entries: [
        .init(album: a, origin: CGPoint(x: 70, y: 40)),
        .init(album: b, origin: CGPoint(x: 900, y: 60)),
        .init(album: c, origin: CGPoint(x: 90, y: 600)),
        .init(album: d, origin: CGPoint(x: 850, y: 700)),
    ]))
    let controller = makeController(store: store)
    controller.tidy()
    let origins = controller.windows.map(\.frame.origin)
    #expect(origins == [CGPoint(x: 333, y: 170), CGPoint(x: 886, y: 170), CGPoint(x: 333, y: 535), CGPoint(x: 886, y: 535)])
    #expect(store.load()?.entries.map(\.origin) == origins)
    #expect(controller.windows.map(\.album) == [a, b, c, d])
}

@MainActor @Test func scrambleMovesCoversToNewSpotsTurnsThemAndKeepsTheOrder() {
    let store = makeStore()
    let start = [CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 300), CGPoint(x: 700, y: 500)]
    store.save(Library(entries: zip([a, b, c], start).map { .init(album: $0, origin: $1) }))
    let controller = makeController(store: store)
    controller.scramble()
    let origins = controller.windows.map(\.coverFrame.origin)
    #expect(origins != start)
    #expect(Set(origins.map { "\($0.x),\($0.y)" }).count == 3)
    #expect(controller.windows.allSatisfy { screen.contains($0.frame) })
    #expect(controller.windows.contains { $0.rotation != 0 })
    #expect(controller.windows.allSatisfy { abs($0.rotation) <= 10 && $0.albumView.rotation == $0.rotation })
    #expect(store.load()?.entries.map(\.origin) == origins)
    #expect(store.load()?.entries.map(\.rotation) == controller.windows.map(\.rotation))
    #expect(controller.windows.map(\.album) == [a, b, c])
}

@MainActor @Test func tidyTurnsEveryCoverStraight() {
    let store = makeStore()
    store.save(Library(entries: [a, b, c].map { .init(album: $0, origin: CGPoint(x: 100, y: 300), rotation: 11) }))
    let controller = makeController(store: store)
    controller.tidy()
    #expect(controller.windows.allSatisfy { $0.rotation == 0 && $0.albumView.rotation == 0 })
    #expect(controller.windows.allSatisfy { $0.frame == $0.coverFrame })
    #expect(store.load()?.entries.map(\.rotation) == [0, 0, 0])
}

@MainActor @Test func tidyingATurnedCoverUsesItsSquareNotItsWindow() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 610, y: 352), rotation: 15)]))
    let controller = makeController(store: store)
    controller.tidy()
    #expect(controller.windows[0].frame == coverFrame(at: CGPoint(x: 610, y: 352)))
}

@MainActor @Test func aTurnedCoversWindowSurroundsItsSquareAndDraggingSavesTheSquare() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 300, y: 300), rotation: 15)]))
    let controller = makeController(store: store)
    let window = controller.windows[0]
    #expect(window.coverFrame == coverFrame(at: CGPoint(x: 300, y: 300)))
    #expect(window.frame.contains(window.coverFrame) && window.frame.width > 220)
    window.setFrameOrigin(CGPoint(x: window.frame.minX + 50, y: window.frame.minY + 20))
    #expect(store.load()?.entries[0].origin == CGPoint(x: 350, y: 320))
    #expect(store.load()?.entries[0].rotation == 15)
}

@MainActor @Test func resizingKeepsTurnedCoversTurnedAndAtTheirTopLeft() {
    let store = makeStore()
    store.save(Library(entries: [.init(album: a, origin: CGPoint(x: 100, y: 300), rotation: -8)]))
    let controller = makeController(store: store)
    controller.setCoverSize(.small)
    #expect(controller.windows[0].coverFrame == coverFrame(at: CGPoint(x: 100, y: 360), size: .small))
    #expect(controller.windows[0].rotation == -8)
}

@MainActor @Test func newCoversStartWithASmallRandomTurnAndStayFullyOnScreen() {
    let store = makeStore()
    let controller = makeController(store: store)
    controller.apply((0..<30).map { album("n\($0)") })
    let rotations = controller.windows.map(\.rotation)
    #expect(rotations.allSatisfy { abs($0) <= 10 } && rotations.contains { $0 != 0 })
    #expect(controller.windows.allSatisfy { screen.contains($0.frame) })
    #expect(store.load()?.entries.map(\.rotation) == rotations)
}
