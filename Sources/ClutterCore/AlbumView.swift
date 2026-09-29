import AppKit

/// Shows one album cover. Drag to move the window; double-click to play;
/// hover to reveal a close button that removes the album.
public final class AlbumView: NSView {
    public static let closeButtonSize: CGFloat = 18
    public static let closeButtonInset: CGFloat = 6

    public let image: NSImage?
    public let closeButton: NSButton = CloseButton()
    public var onDoubleClick: (() -> Void)?
    public var onClose: (() -> Void)?

    public init(image: NSImage?) {
        self.image = image
        super.init(frame: .zero)
        configureCloseButton()
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func draw(_ dirtyRect: NSRect) {
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

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let size = Self.closeButtonSize
        let inset = Self.closeButtonInset
        closeButton.frame = NSRect(x: inset, y: newSize.height - inset - size, width: size, height: size)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    public override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
    }

    public override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    private func configureCloseButton() {
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove album")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        closeButton.layer?.cornerRadius = Self.closeButtonSize / 2
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
    }

    @objc private func closeClicked() {
        onClose?()
    }
}

/// Clicks on it count even when the cover's window isn't active.
private final class CloseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
