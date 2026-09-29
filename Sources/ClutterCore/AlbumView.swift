import AppKit

/// Shows one album cover. Drag to move the window; double-click to play. Hovering shows the artist
/// and title along the bottom, unless `showsInfoOnHover` is off. Hovering with Option held shows a
/// close button, which asks whether to remove the album from the Spotify library.
public final class AlbumView: NSView {
    /// Nil shows a gray placeholder.
    public var image: NSImage? {
        didSet { needsDisplay = true }
    }
    public let artist: String
    public let title: String
    public var showsInfoOnHover = true {
        didSet { needsDisplay = true }
    }
    public var onDoubleClick: (() -> Void)?
    /// Called on every click, before dragging or playing.
    public var onMouseDown: (() -> Void)?
    /// Called when Remove is clicked in the confirmation overlay.
    public var onRemove: (() -> Void)?

    /// Where the Option key's state comes from; tests replace it.
    var modifierFlags: () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }

    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    private var isOptionDown = false {
        didSet { needsDisplay = true }
    }
    /// Stays up, whatever the mouse and Option key do, until Remove or Cancel is clicked.
    var isConfirmingRemoval = false {
        didSet {
            removeButton.isHidden = !isConfirmingRemoval
            cancelButton.isHidden = !isConfirmingRemoval
            needsLayout = true
            needsDisplay = true
        }
    }
    var isShowingInfo: Bool { isHovering && showsInfoOnHover && !isConfirmingRemoval }
    var isShowingCloseButton: Bool { isHovering && isOptionDown && !isConfirmingRemoval }

    let removeButton = FirstClickButton(title: "Remove", target: nil, action: nil)
    let cancelButton = FirstClickButton(title: "Cancel", target: nil, action: nil)
    /// Checks the Option key while hovering. Covers usually sit behind the active app, so they
    /// don't get `flagsChanged` events, and watching keys globally would need Accessibility access.
    private var modifierTimer: Timer?

    public init(image: NSImage?, artist: String = "", title: String = "") {
        self.image = image
        self.artist = artist
        self.title = title
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

    public override func draw(_ dirtyRect: NSRect) {
        drawCover()
        if isShowingInfo { drawInfo() }
        if isShowingCloseButton { drawCloseButton() }
        if isConfirmingRemoval { drawConfirmation() }
    }

    private func drawCover() {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            NSColor.darkGray.setFill()
            bounds.fill()
            return
        }
        // Aspect-fill: scale to cover the view, centered.
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        image.draw(in: NSRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height))
    }

    static let artistFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let titleFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 13)
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.italic), size: base.pointSize) ?? base
    }()

    /// Dims a band along the bottom, just tall enough for the artist over the title, which wrap and
    /// truncate to fit the cover.
    private func drawInfo() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSMutableAttributedString(string: artist, attributes: [
            .font: Self.artistFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        text.append(NSAttributedString(string: "\n" + title, attributes: [
            .font: Self.titleFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .paragraphStyle: paragraph,
        ]))

        let padding: CGFloat = 10
        let available = bounds.insetBy(dx: padding + 4, dy: padding)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let height = min(ceil(text.boundingRect(with: available.size, options: options).height), available.height)

        NSColor.black.withAlphaComponent(0.65).setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height + padding * 2).fill(using: .sourceOver)
        text.draw(with: NSRect(x: available.minX, y: bounds.minY + padding, width: available.width, height: height), options: options)
    }

    /// In view coordinates, which start at the bottom left.
    var closeButtonRect: NSRect {
        let size: CGFloat = 20
        return NSRect(x: bounds.minX + 8, y: bounds.maxY - 8 - size, width: size, height: size)
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

    private static let confirmationText: NSAttributedString = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: "Remove from Spotify library?", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
    }()
    private static let confirmationSpacing: CGFloat = 10

    private var confirmationTextWidth: CGFloat { bounds.width - 20 }

    private var confirmationTextHeight: CGFloat {
        let size = NSSize(width: confirmationTextWidth, height: .greatestFiniteMagnitude)
        return ceil(Self.confirmationText.boundingRect(with: size, options: .usesLineFragmentOrigin).height)
    }

    /// Dims the whole cover behind the question; the buttons are subviews, placed by `layout`.
    private func drawConfirmation() {
        NSColor.black.withAlphaComponent(0.75).setFill()
        bounds.fill(using: .sourceOver)
        let textRect = NSRect(
            x: bounds.midX - confirmationTextWidth / 2, y: removeButton.frame.maxY + Self.confirmationSpacing,
            width: confirmationTextWidth, height: confirmationTextHeight
        )
        Self.confirmationText.draw(with: textRect, options: .usesLineFragmentOrigin)
    }

    /// Centers the question above Cancel and Remove, side by side.
    public override func layout() {
        super.layout()
        removeButton.sizeToFit()
        cancelButton.sizeToFit()
        let gap: CGFloat = 8
        let rowWidth = cancelButton.frame.width + gap + removeButton.frame.width
        let rowHeight = max(cancelButton.frame.height, removeButton.frame.height)
        let blockHeight = confirmationTextHeight + Self.confirmationSpacing + rowHeight
        let y = (bounds.midY - blockHeight / 2).rounded()
        let x = (bounds.midX - rowWidth / 2).rounded()
        cancelButton.setFrameOrigin(NSPoint(x: x, y: y))
        removeButton.setFrameOrigin(NSPoint(x: cancelButton.frame.maxX + gap, y: y))
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
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
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovering = true
        startWatchingModifierKeys()
    }

    public override func mouseExited(with event: NSEvent) {
        isHovering = false
        stopWatchingModifierKeys()
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if isShowingCloseButton, closeButtonRect.contains(convert(event.locationInWindow, from: nil)) {
            isConfirmingRemoval = true
            return
        }
        onMouseDown?()
        if event.clickCount == 2, !isConfirmingRemoval {
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
