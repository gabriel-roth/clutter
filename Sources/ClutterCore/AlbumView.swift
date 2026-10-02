import AppKit

/// Shows one album cover. Drag to move the window; double-click to play, which flashes the banner. Hovering shows the artist
/// and title along the bottom, unless `showsInfoOnHover` is off. Hovering with Option held shows a
/// close button, which asks `removalQuestion` before removing the album.
public final class AlbumView: NSView {
    /// Nil shows a gray placeholder.
    public var image: NSImage? {
        didSet { needsDisplay = true }
    }
    public let artist: String
    public let title: String
    /// Asked over the cover when the close button is clicked, above Cancel and Remove.
    public let removalQuestion: String
    public var showsInfoOnHover = true {
        didSet { needsDisplay = true }
    }
    /// Degrees counterclockwise the cover is turned about its center. The view is then bigger than
    /// the cover, which is drawn in the middle of it, and only the cover takes clicks.
    public var rotation: CGFloat = 0 {
        didSet { needsDisplay = true; needsLayout = true }
    }
    /// The cover's side; nil means the cover fills the view.
    public var coverSide: CGFloat? {
        didSet { needsDisplay = true; needsLayout = true }
    }
    public var onDoubleClick: (() -> Void)?
    /// Called on every click, before dragging or playing.
    public var onMouseDown: (() -> Void)?
    /// Called when Remove is clicked in the confirmation overlay.
    public var onRemove: (() -> Void)?

    /// Where the Option key's state comes from; tests replace it.
    var modifierFlags: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }

    /// Leaving the cover also takes back the question about removing it.
    private var isHovering = false {
        didSet {
            needsDisplay = true
            if !isHovering { isConfirmingRemoval = false }
        }
    }
    private var isOptionDown = false {
        didSet { needsDisplay = true }
    }
    /// Stays up, whatever the Option key does, until Remove or Cancel is clicked or the pointer leaves the cover.
    var isConfirmingRemoval = false {
        didSet {
            removeButton.isHidden = !isConfirmingRemoval
            cancelButton.isHidden = !isConfirmingRemoval
            needsLayout = true
            needsDisplay = true
        }
    }
    /// True for a moment after a double-click, so the banner lights up even when hover info is off.
    private(set) var isFlashingInfo = false {
        didSet { needsDisplay = true; if isFlashingInfo != oldValue { onFlashingInfoChange?(isFlashingInfo) } }
    }
    /// Tests watch the flash through this instead of sampling the clock.
    var onFlashingInfoChange: ((Bool) -> Void)?
    /// Seconds lit, dark, lit; the banner goes dark again after the last.
    static let flashPattern: [TimeInterval] = [0.1, 0.08, 0.1]
    private var flashTimers: [Timer] = []
    var isShowingInfo: Bool { (isHovering && showsInfoOnHover || isFlashingInfo) && !isConfirmingRemoval }
    var isShowingCloseButton: Bool { isHovering && isOptionDown && !isConfirmingRemoval }

    let removeButton = FirstClickButton(title: "Remove", target: nil, action: nil)
    let cancelButton = FirstClickButton(title: "Cancel", target: nil, action: nil)
    /// Checks the Option key while hovering. Covers usually sit behind the active app, so they
    /// don't get `flagsChanged` events, and watching keys globally would need Accessibility access.
    private var modifierTimer: Timer?

    public init(image: NSImage?, artist: String = "", title: String = "", removalQuestion: String = "Remove from Spotify library?") {
        self.image = image
        self.artist = artist
        self.title = title
        self.removalQuestion = removalQuestion
        super.init(frame: .zero)
        removeButton.hasDestructiveAction = true
        cancelButton.keyEquivalent = "\u{1b}"
        for (button, action) in [(removeButton, #selector(confirmRemoval)), (cancelButton, #selector(cancelRemoval))] {
            button.target = self
            button.action = action
            button.controlSize = .small
            button.appearance = NSAppearance(named: .darkAqua)
            button.isHidden = true
            addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The cover in its own coordinates, before it's turned and centered in the view.
    private var coverBounds: NSRect {
        coverSide.map { NSRect(x: 0, y: 0, width: $0, height: $0) } ?? bounds
    }

    private var rotationRadians: CGFloat { rotation * .pi / 180 }

    /// Where a point in the view falls on the cover.
    private func coverPoint(fromViewPoint point: NSPoint) -> NSPoint {
        let (dx, dy) = (point.x - bounds.midX, point.y - bounds.midY)
        let (cosine, sine) = (cos(-rotationRadians), sin(-rotationRadians))
        return NSPoint(x: dx * cosine - dy * sine + coverBounds.midX, y: dx * sine + dy * cosine + coverBounds.midY)
    }

    /// Where a point on the cover falls in the view.
    private func viewPoint(fromCoverPoint point: NSPoint) -> NSPoint {
        let (dx, dy) = (point.x - coverBounds.midX, point.y - coverBounds.midY)
        let (cosine, sine) = (cos(rotationRadians), sin(rotationRadians))
        return NSPoint(x: dx * cosine - dy * sine + bounds.midX, y: dx * sine + dy * cosine + bounds.midY)
    }

    private func coverContains(viewPoint point: NSPoint) -> Bool {
        coverBounds.contains(coverPoint(fromViewPoint: point))
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard rotation != 0, let superview else { return super.hitTest(point) }
        return coverContains(viewPoint: convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let turn = NSAffineTransform()
        turn.translateX(by: bounds.midX, yBy: bounds.midY)
        turn.rotate(byRadians: rotationRadians)
        turn.translateX(by: -coverBounds.midX, yBy: -coverBounds.midY)
        turn.concat()
        coverBounds.clip()
        drawCover()
        if isShowingInfo { drawInfo() }
        if isShowingCloseButton { drawCloseButton() }
        if isConfirmingRemoval { drawConfirmation() }
    }

    private func drawCover() {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            NSColor.darkGray.setFill()
            coverBounds.fill()
            return
        }
        // Aspect-fill: scale to cover the view, centered.
        let scale = max(coverBounds.width / image.size.width, coverBounds.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        image.draw(in: NSRect(x: coverBounds.midX - width / 2, y: coverBounds.midY - height / 2, width: width, height: height))
    }

    static let artistFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let titleFont = italicSystemFont(ofSize: 13)
    /// A compilation shows no artist, so its title gets the artist's size.
    static let compilationTitleFont = italicSystemFont(ofSize: 15)

    private static func italicSystemFont(ofSize size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? base
    }

    /// The artist over the title, or just the title, bigger, for a compilation.
    var infoText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .paragraphStyle: paragraph,
        ]
        if Album.isCompilation(artist: artist) {
            return NSAttributedString(string: title, attributes: titleAttributes.merging([.font: Self.compilationTitleFont]) { $1 })
        }
        let text = NSMutableAttributedString(string: artist, attributes: [
            .font: Self.artistFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        text.append(NSAttributedString(string: "\n" + title, attributes: titleAttributes))
        return text
    }

    /// Dims a band along the bottom, just tall enough for the info text, which wraps and truncates
    /// to fit the cover.
    private func drawInfo() {
        let text = NSMutableAttributedString(attributedString: infoText)
        if isFlashingInfo {
            text.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: text.length))
        }

        let padding: CGFloat = 10
        let available = coverBounds.insetBy(dx: padding + 4, dy: padding)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let height = min(ceil(text.boundingRect(with: available.size, options: options).height), available.height)

        (isFlashingInfo ? NSColor.white.withAlphaComponent(0.9) : NSColor.black.withAlphaComponent(0.65)).setFill()
        NSRect(x: coverBounds.minX, y: coverBounds.minY, width: coverBounds.width, height: height + padding * 2).fill(using: .sourceOver)
        text.draw(with: NSRect(x: available.minX, y: coverBounds.minY + padding, width: available.width, height: height), options: options)
    }

    /// In cover coordinates, which start at the bottom left.
    var closeButtonRect: NSRect {
        let size: CGFloat = 20
        return NSRect(x: coverBounds.minX + 8, y: coverBounds.maxY - 8 - size, width: size, height: size)
    }

    private func drawCloseButton() {
        let circle = NSBezierPath(ovalIn: closeButtonRect)
        NSColor.black.withAlphaComponent(0.75).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
        let cross = NSBezierPath()
        let arm = closeButtonRect.insetBy(dx: 6.5, dy: 6.5)
        cross.move(to: NSPoint(x: arm.minX, y: arm.minY))
        cross.line(to: NSPoint(x: arm.maxX, y: arm.maxY))
        cross.move(to: NSPoint(x: arm.minX, y: arm.maxY))
        cross.line(to: NSPoint(x: arm.maxX, y: arm.minY))
        cross.lineWidth = 2
        cross.lineCapStyle = .round
        cross.stroke()
    }

    var confirmationText: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: removalQuestion, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
    }
    private static let confirmationSpacing: CGFloat = 10

    private var confirmationTextWidth: CGFloat { coverBounds.width - 20 }

    private var confirmationTextHeight: CGFloat {
        let size = NSSize(width: confirmationTextWidth, height: .greatestFiniteMagnitude)
        return ceil(confirmationText.boundingRect(with: size, options: .usesLineFragmentOrigin).height)
    }

    /// Dims the whole cover behind the question; the buttons are subviews, placed by `layout`.
    private func drawConfirmation() {
        NSColor.black.withAlphaComponent(0.75).setFill()
        coverBounds.fill(using: .sourceOver)
        let textRect = NSRect(
            x: coverBounds.midX - confirmationTextWidth / 2, y: confirmationRowOrigin.y + confirmationRowHeight + Self.confirmationSpacing,
            width: confirmationTextWidth, height: confirmationTextHeight
        )
        confirmationText.draw(with: textRect, options: .usesLineFragmentOrigin)
    }

    private var confirmationRowHeight: CGFloat {
        max(cancelButton.frame.height, removeButton.frame.height)
    }

    /// Where the row of Cancel and Remove starts on the cover, centered with the question above it.
    private var confirmationRowOrigin: NSPoint {
        let blockHeight = confirmationTextHeight + Self.confirmationSpacing + confirmationRowHeight
        return NSPoint(x: (coverBounds.midX - confirmationRowWidth / 2).rounded(), y: (coverBounds.midY - blockHeight / 2).rounded())
    }

    private static let buttonGap: CGFloat = 8

    private var confirmationRowWidth: CGFloat {
        cancelButton.frame.width + Self.buttonGap + removeButton.frame.width
    }

    /// Centers the question above Cancel and Remove, side by side. On a turned cover each button is
    /// placed where it falls on the cover and turned with it about its own center.
    public override func layout() {
        super.layout()
        // Upright first, so sizing and `frame` describe the button itself rather than its turned bounding box.
        for button in [removeButton, cancelButton] {
            button.frameCenterRotation = 0
            button.sizeToFit()
        }
        let origin = confirmationRowOrigin
        let cancelSpot = NSPoint(x: origin.x, y: origin.y)
        let removeSpot = NSPoint(x: origin.x + cancelButton.frame.width + Self.buttonGap, y: origin.y)
        for (button, spot) in [(cancelButton, cancelSpot), (removeButton, removeSpot)] {
            if rotation == 0 {
                button.setFrameOrigin(spot)
            } else {
                let center = viewPoint(fromCoverPoint: NSPoint(x: spot.x + button.frame.width / 2, y: spot.y + button.frame.height / 2))
                button.setFrameOrigin(NSPoint(x: center.x - button.frame.width / 2, y: center.y - button.frame.height / 2))
                button.frameCenterRotation = rotation
            }
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    /// Inverts the banner twice, echoing the double-click, to show it was received.
    private func flashInfo() {
        flashTimers.forEach { $0.invalidate() }
        isFlashingInfo = true
        var elapsed: TimeInterval = 0
        flashTimers = Self.flashPattern.enumerated().map { index, duration in
            elapsed += duration
            let timer = Timer(timeInterval: elapsed, repeats: false) { [weak self] _ in
                self?.isFlashingInfo = index % 2 == 1
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        }
    }

    @objc private func confirmRemoval() {
        isConfirmingRemoval = false
        onRemove?()
    }

    @objc private func cancelRemoval() {
        isConfirmingRemoval = false
    }

    /// Reads whether Option is held, which with hovering decides whether the close button shows.
    func updateModifierKeys() {
        isOptionDown = modifierFlags().contains(.option)
    }

    private func startWatchingModifierKeys() {
        updateModifierKeys()
        modifierTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, target: self, selector: #selector(modifierTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }

    private func stopWatchingModifierKeys() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        isOptionDown = false
    }

    @objc private func modifierTimerFired() {
        // A cover closed while hovered never gets mouseExited.
        guard window?.isVisible == true else { return stopWatchingModifierKeys() }
        updateModifierKeys()
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if isHovering { updateModifierKeys() }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Always active, since covers sit on the desktop while other apps are in front.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovering = pointerIsOnCover(event)
        startWatchingModifierKeys()
    }

    /// The tracking area is the whole window, corners included, so a turned cover checks the pointer itself.
    public override func mouseMoved(with event: NSEvent) {
        isHovering = pointerIsOnCover(event)
    }

    private func pointerIsOnCover(_ event: NSEvent) -> Bool {
        rotation == 0 || coverContains(viewPoint: convert(event.locationInWindow, from: nil))
    }

    public override func mouseExited(with event: NSEvent) {
        isHovering = false
        stopWatchingModifierKeys()
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if isShowingCloseButton, closeButtonRect.contains(coverPoint(fromViewPoint: convert(event.locationInWindow, from: nil))) {
            isConfirmingRemoval = true
            return
        }
        onMouseDown?()
        if event.clickCount == 2, !isConfirmingRemoval {
            flashInfo()
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }
}

/// Takes the click that activates the app, so one click works while another app is in front.
final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
