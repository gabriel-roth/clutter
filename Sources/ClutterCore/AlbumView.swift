import AppKit

/// Shows one album cover. Drag to move the window; double-click to play.
public final class AlbumView: NSView {
    public let image: NSImage?
    public var onDoubleClick: (() -> Void)?
    /// Called on every click, before dragging or playing.
    public var onMouseDown: (() -> Void)?

    public init(image: NSImage?) {
        self.image = image
        super.init(frame: .zero)
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

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }
}
