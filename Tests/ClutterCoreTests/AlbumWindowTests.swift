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
    let window = AlbumWindow(album: Album.starters[0], image: nil, frame: frame)
    #expect(window.styleMask == [.borderless])
    #expect(window.hasShadow)
    #expect(window.canBecomeKey)
    #expect(window.frame == frame)
    #expect(window.contentView === window.albumView)
    #expect(window.album == Album.starters[0])
}

@MainActor @Test func firstClickOnAnInactiveCoverIsHandled() {
    // Otherwise the first click only activates the window, so dragging needs two tries.
    #expect(AlbumView(image: nil).acceptsFirstMouse(for: mouseDown(clickCount: 1)))
}

@MainActor
private func enterExit(_ type: NSEvent.EventType) -> NSEvent {
    NSEvent.enterExitEvent(
        with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
    )!
}

@MainActor @Test func closeButtonIsHiddenUntilThePointerEnters() {
    let view = AlbumView(image: nil)
    #expect(view.closeButton.isHidden)
    view.mouseEntered(with: enterExit(.mouseEntered))
    #expect(!view.closeButton.isHidden)
    view.mouseExited(with: enterExit(.mouseExited))
    #expect(view.closeButton.isHidden)
}

@MainActor @Test func viewTracksHoverEvenWhenClutterIsInactive() {
    let view = AlbumView(image: nil)
    view.updateTrackingAreas()
    #expect(view.trackingAreas.contains { $0.options.contains([.mouseEnteredAndExited, .activeAlways, .inVisibleRect]) })
}

@MainActor @Test func clickingCloseButtonCallsOnClose() {
    let view = AlbumView(image: nil)
    var closed = 0
    view.onClose = { closed += 1 }
    view.mouseEntered(with: enterExit(.mouseEntered))
    view.closeButton.performClick(nil)
    #expect(closed == 1)
}

@MainActor @Test func closeButtonSitsInTheTopLeftCorner() {
    let view = AlbumView(image: nil)
    view.setFrameSize(CGSize(width: 220, height: 220))
    #expect(view.closeButton.frame == CGRect(x: 6, y: 196, width: 18, height: 18))
    #expect(view.closeButton.superview === view)
}

@MainActor @Test func closeButtonWorksOnTheFirstClick() {
    #expect(AlbumView(image: nil).closeButton.acceptsFirstMouse(for: mouseDown(clickCount: 1)))
}
