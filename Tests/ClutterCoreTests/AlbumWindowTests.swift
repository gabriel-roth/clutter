import AppKit
import Testing
@testable import ClutterCore

@MainActor
private func mouseDown(clickCount: Int) -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1
    )!
}

@MainActor @Test func doubleClickFiresCallback() {
    let view = AlbumView(image: nil)
    var fired = 0
    view.onDoubleClick = { fired += 1 }
    view.mouseDown(with: mouseDown(clickCount: 2))
    #expect(fired == 1)
}

@MainActor @Test func singleClickDoesNotFireCallback() {
    let view = AlbumView(image: nil)
    var fired = 0
    view.onDoubleClick = { fired += 1 }
    view.mouseDown(with: mouseDown(clickCount: 1))
    #expect(fired == 0)
}

@MainActor @Test func viewDrawsWithoutArtwork() {
    let view = AlbumView(image: nil)
    view.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    #expect(rep.colorAt(x: 25, y: 25)?.alphaComponent == 1)
}

@MainActor @Test func windowIsABorderlessCoverThatCanBecomeKey() {
    let frame = CGRect(x: 100, y: 100, width: 220, height: 220)
    let album = Album(title: "T", artist: "A", spotifyURI: "spotify:album:t", artworkName: "t")
    let window = AlbumWindow(album: album, image: nil, frame: frame)
    #expect(window.styleMask == [.borderless])
    #expect(window.hasShadow)
    #expect(window.canBecomeKey)
    #expect(window.frame == frame)
    #expect(window.contentView === window.albumView)
    #expect(window.album == album)
}

@MainActor @Test func firstClickOnAnInactiveCoverIsHandled() {
    // Otherwise the first click only activates the window, so dragging needs two tries.
    #expect(AlbumView(image: nil).acceptsFirstMouse(for: mouseDown(clickCount: 1)))
}
