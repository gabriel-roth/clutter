import AppKit

/// Shows one album cover. Drag to move the window; double-click to play. Hovering shows the artist
/// and title along the bottom, unless `showsInfoOnHover` is off.
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

    private var isHovering = false {
        didSet { needsDisplay = true }
    }
    var isShowingInfo: Bool { isHovering && showsInfoOnHover }

    public init(image: NSImage?, artist: String = "", title: String = "") {
        self.image = image
        self.artist = artist
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func draw(_ dirtyRect: NSRect) {
        drawCover()
        if isShowingInfo { drawInfo() }
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

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Always active, since covers sit on the desktop while other apps are in front.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    public override func mouseExited(with event: NSEvent) {
        isHovering = false
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
