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

@MainActor @Test func everyClickFiresOnMouseDown() {
    let view = AlbumView(image: nil)
    var fired = 0
    view.onMouseDown = { fired += 1 }
    view.mouseDown(with: mouseDown(clickCount: 1))
    #expect(fired == 1)
    view.mouseDown(with: mouseDown(clickCount: 2))
    #expect(fired == 2)
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

@MainActor
private func enterExit(_ type: NSEvent.EventType) -> NSEvent {
    NSEvent.enterExitEvent(
        with: type, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
    )!
}

@MainActor
private func whiteImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 10, height: 10))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 10, height: 10).fill()
    image.unlockFocus()
    return image
}

/// Brightness of each pixel row, top to bottom, at the view's left edge, away from any overlay text.
@MainActor
private func edgeBrightness(of view: AlbumView) -> [CGFloat] {
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return (0..<rep.pixelsHigh).map { rep.colorAt(x: 1, y: $0)!.usingColorSpace(.deviceRGB)!.brightnessComponent }
}

/// Brightness of the view's top and bottom edges, away from any overlay text.
@MainActor
private func topAndBottomBrightness(of view: AlbumView) -> (top: CGFloat, bottom: CGFloat) {
    let rows = edgeBrightness(of: view)
    return (rows[1], rows[rows.count - 2])
}

/// How many pixel rows the overlay band covers.
@MainActor
private func bandHeight(of view: AlbumView) -> Int {
    edgeBrightness(of: view).filter { $0 < 0.5 }.count
}

@MainActor @Test func hoveringDimsTheCoverUntilTheMouseLeaves() {
    let view = AlbumView(image: whiteImage(), artist: "Artist", title: "Title")
    view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
    #expect(topAndBottomBrightness(of: view).bottom > 0.95)
    view.mouseEntered(with: enterExit(.mouseEntered))
    #expect(view.isShowingInfo)
    #expect(topAndBottomBrightness(of: view).bottom < 0.5)
    view.mouseExited(with: enterExit(.mouseExited))
    #expect(!view.isShowingInfo)
    #expect(topAndBottomBrightness(of: view).bottom > 0.95)
}

@MainActor @Test func hoveringShowsNothingWhenInfoIsTurnedOff() {
    let view = AlbumView(image: whiteImage(), artist: "Artist", title: "Title")
    view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
    view.showsInfoOnHover = false
    view.mouseEntered(with: enterExit(.mouseEntered))
    #expect(!view.isShowingInfo)
    #expect(topAndBottomBrightness(of: view).bottom > 0.95)
    view.showsInfoOnHover = true
    #expect(view.isShowingInfo)
}

@MainActor @Test func viewTracksTheMouseEvenWhenTheAppIsInactive() {
    let view = AlbumView(image: nil)
    view.updateTrackingAreas()
    let options = view.trackingAreas.map(\.options)
    #expect(options.contains { $0.contains([.mouseEnteredAndExited, .activeAlways, .inVisibleRect]) })
}

@MainActor @Test func windowGivesItsViewTheAlbumArtistAndTitle() {
    let album = Album(title: "T", artist: "A", spotifyURI: "spotify:album:t", artworkName: "t")
    let window = AlbumWindow(album: album, image: nil, frame: CGRect(x: 0, y: 0, width: 160, height: 160))
    #expect(window.albumView.artist == "A")
    #expect(window.albumView.title == "T")
}

@MainActor @Test func overlayCoversOnlyTheBottomAndGrowsWithTheText() {
    let short = AlbumView(image: whiteImage(), artist: "Artist", title: "Title")
    let long = AlbumView(image: whiteImage(), artist: "Godspeed You! Black Emperor", title: "Lift Your Skinny Fists Like Antennas to Heaven!")
    for view in [short, long] {
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        view.mouseEntered(with: enterExit(.mouseEntered))
        #expect(topAndBottomBrightness(of: view).top > 0.95)
        #expect(topAndBottomBrightness(of: view).bottom < 0.5)
    }
    #expect(bandHeight(of: long) > bandHeight(of: short))
}

@MainActor @Test func titleFontIsItalic() {
    #expect(AlbumView.titleFont.fontDescriptor.symbolicTraits.contains(.italic))
    #expect(!AlbumView.artistFont.fontDescriptor.symbolicTraits.contains(.italic))
}
