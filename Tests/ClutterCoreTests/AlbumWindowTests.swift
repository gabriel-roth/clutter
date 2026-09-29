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

@MainActor @Test func doubleClickFlashesBannerEvenWithHoverInfoOff() {
    let view = AlbumView(image: nil, artist: "A", title: "T")
    view.showsInfoOnHover = false
    view.mouseDown(with: mouseDown(clickCount: 2))
    #expect(view.isFlashingInfo)
    #expect(view.isShowingInfo)
}

@MainActor @Test func singleClickDoesNotFlashBanner() {
    let view = AlbumView(image: nil, artist: "A", title: "T")
    view.mouseDown(with: mouseDown(clickCount: 1))
    #expect(!view.isFlashingInfo)
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

/// A cover whose modifier keys are read from `keys` instead of the keyboard.
@MainActor
private func coverWithKeys(_ keys: Box<NSEvent.ModifierFlags>) -> AlbumView {
    let view = AlbumView(image: whiteImage(), artist: "Artist", title: "Title")
    view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
    view.modifierFlags = { keys.value }
    return view
}

@MainActor
private func mouseDown(at point: CGPoint, clickCount: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1
    )!
}

@MainActor @Test func holdingOptionWhileHoveringShowsTheCloseButtonUntilOptionIsReleased() {
    let keys = Box<NSEvent.ModifierFlags>([])
    let view = coverWithKeys(keys)
    view.mouseEntered(with: enterExit(.mouseEntered))
    #expect(!view.isShowingCloseButton)
    keys.value = [.option]
    view.updateModifierKeys()
    #expect(view.isShowingCloseButton)
    keys.value = []
    view.updateModifierKeys()
    #expect(!view.isShowingCloseButton)
}

@MainActor @Test func optionAlreadyHeldShowsTheCloseButtonOnEntering() {
    let keys = Box<NSEvent.ModifierFlags>([.option])
    let view = coverWithKeys(keys)
    view.mouseEntered(with: enterExit(.mouseEntered))
    #expect(view.isShowingCloseButton)
    view.mouseExited(with: enterExit(.mouseExited))
    #expect(!view.isShowingCloseButton)
}

@MainActor @Test func optionWithoutHoveringShowsNoCloseButton() {
    let keys = Box<NSEvent.ModifierFlags>([.option])
    let view = coverWithKeys(keys)
    view.updateModifierKeys()
    #expect(!view.isShowingCloseButton)
}

@MainActor @Test func clickingTheCloseButtonAsksForConfirmationThatOutlastsOptionAndTheMouse() {
    let keys = Box<NSEvent.ModifierFlags>([.option])
    let view = coverWithKeys(keys)
    var dragsOrClicks = 0
    view.onMouseDown = { dragsOrClicks += 1 }
    view.mouseEntered(with: enterExit(.mouseEntered))
    view.mouseDown(with: mouseDown(at: CGPoint(x: view.closeButtonRect.midX, y: view.closeButtonRect.midY)))
    #expect(view.isConfirmingRemoval)
    #expect(dragsOrClicks == 0)
    #expect(!view.isShowingCloseButton)
    #expect(!view.isShowingInfo)
    #expect(!view.removeButton.isHidden && !view.cancelButton.isHidden)
    keys.value = []
    view.updateModifierKeys()
    view.mouseExited(with: enterExit(.mouseExited))
    #expect(view.isConfirmingRemoval)
    // The whole cover is dimmed, not just the bottom.
    #expect(topAndBottomBrightness(of: view).top < 0.5)
}

@MainActor @Test func clickingElsewhereWithOptionHeldDoesNotAskForConfirmation() {
    let keys = Box<NSEvent.ModifierFlags>([.option])
    let view = coverWithKeys(keys)
    view.mouseEntered(with: enterExit(.mouseEntered))
    view.mouseDown(with: mouseDown(at: CGPoint(x: 150, y: 10)))
    #expect(!view.isConfirmingRemoval)
}

@MainActor @Test func theCloseButtonIsInTheTopLeftCorner() {
    let view = coverWithKeys(Box([]))
    #expect(view.closeButtonRect.minX < 20)
    #expect(view.closeButtonRect.maxY > 140)
}

@MainActor @Test func cancelDismissesTheConfirmationWithoutRemoving() {
    let view = coverWithKeys(Box([.option]))
    var removed = 0
    view.onRemove = { removed += 1 }
    view.isConfirmingRemoval = true
    view.cancelButton.performClick(nil)
    #expect(!view.isConfirmingRemoval)
    #expect(view.removeButton.isHidden && view.cancelButton.isHidden)
    #expect(removed == 0)
}

@MainActor @Test func removeDismissesTheConfirmationAndRemoves() {
    let view = coverWithKeys(Box([]))
    var removed = 0
    view.onRemove = { removed += 1 }
    view.isConfirmingRemoval = true
    view.removeButton.performClick(nil)
    #expect(!view.isConfirmingRemoval)
    #expect(removed == 1)
}

@MainActor @Test func doubleClickingDoesNotPlayWhileConfirming() {
    let view = coverWithKeys(Box([]))
    var played = 0
    view.onDoubleClick = { played += 1 }
    view.isConfirmingRemoval = true
    view.mouseDown(with: mouseDown(at: CGPoint(x: 80, y: 80), clickCount: 2))
    #expect(played == 0)
}

@MainActor @Test func confirmationButtonsFitOnASmallCoverAndTakeTheFirstClick() {
    let view = coverWithKeys(Box([]))
    view.isConfirmingRemoval = true
    view.layoutSubtreeIfNeeded()
    for button in [view.removeButton, view.cancelButton] {
        #expect(view.bounds.contains(button.frame))
        #expect(button.acceptsFirstMouse(for: nil))
    }
    #expect(!view.removeButton.frame.intersects(view.cancelButton.frame))
}

@MainActor @Test func aTurnedCoverSitsCenteredInATransparentWindowJustBigEnoughForIt() {
    let cover = CGRect(x: 100, y: 100, width: 220, height: 220)
    let album = Album(title: "T", artist: "A", spotifyURI: "spotify:album:t", artworkName: "t")
    let window = AlbumWindow(album: album, image: nil, frame: cover, rotation: 15)
    #expect(!window.isOpaque && window.backgroundColor == .clear)
    #expect(window.frame == cover.insetBy(dx: -25, dy: -25))
    #expect(window.coverFrame == cover)
    #expect(window.albumView.rotation == 15 && window.albumView.coverSide == 220)
    window.setCover(frame: cover, rotation: 0)
    #expect(window.frame == cover && window.coverFrame == cover)
}

@MainActor @Test func aTurnedCoverTakesClicksOnlyWhereTheCoverIs() {
    let container = NSView(frame: CGRect(x: 0, y: 0, width: 270, height: 270))
    let view = AlbumView(image: nil)
    view.frame = container.bounds
    view.coverSide = 220
    view.rotation = 15
    container.addSubview(view)
    #expect(view.hitTest(CGPoint(x: 135, y: 135)) != nil)
    #expect(view.hitTest(CGPoint(x: 1, y: 1)) == nil)
    #expect(view.hitTest(CGPoint(x: 269, y: 269)) == nil)
    view.rotation = 0
    view.coverSide = nil
    #expect(view.hitTest(CGPoint(x: 1, y: 1)) != nil)
}

@MainActor @Test func hoveringOnlyCountsOnTheTurnedCover() {
    let view = AlbumView(image: nil, artist: "A", title: "T")
    view.frame = CGRect(x: 0, y: 0, width: 270, height: 270)
    view.coverSide = 220
    view.rotation = 15
    func moved(to point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    }
    view.mouseMoved(with: moved(to: CGPoint(x: 1, y: 1)))
    #expect(!view.isShowingInfo)
    view.mouseMoved(with: moved(to: CGPoint(x: 135, y: 135)))
    #expect(view.isShowingInfo)
    view.mouseExited(with: enterExit(.mouseExited))
}

@MainActor @Test func aTurnedCoverDrawsTransparentCornersAndAnOpaqueCenter() {
    let view = AlbumView(image: nil)
    view.frame = CGRect(x: 0, y: 0, width: 270, height: 270)
    view.coverSide = 220
    view.rotation = 15
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    #expect(rep.colorAt(x: 135, y: 135)?.alphaComponent == 1)
    #expect(rep.colorAt(x: 1, y: 1)?.alphaComponent == 0)
}
