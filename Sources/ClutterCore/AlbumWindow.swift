import AppKit

/// A borderless window that is nothing but an album cover. A turned cover sits in the middle of a
/// transparent window just big enough to hold it; the window's `frame` is that box, while
/// `coverFrame` is the cover's own square.
public final class AlbumWindow: NSWindow {
    public let album: Album
    public let albumView: AlbumView
    public private(set) var rotation: CGFloat
    private var coverSize: CGFloat

    /// `frame` is the cover's square, `rotation` how far it's turned, in degrees counterclockwise.
    public init(album: Album, image: NSImage?, frame: CGRect, rotation: CGFloat = 0) {
        self.album = album
        self.albumView = AlbumView(image: image, artist: album.artist, title: album.title)
        self.rotation = rotation
        self.coverSize = frame.width
        super.init(contentRect: Self.windowFrame(cover: frame, rotation: rotation), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        contentView = albumView
        hasShadow = true
        isReleasedWhenClosed = false
        title = album.isCompilation ? album.title : "\(album.title) — \(album.artist)"
        albumView.coverSide = coverSize
        albumView.rotation = rotation
    }

    public override var canBecomeKey: Bool { true }

    /// Turned covers reach past the screen edge by design; don't let AppKit pull them back.
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// The cover's square, whatever its turn.
    public var coverFrame: CGRect {
        let margin = Placement.rotationMargin(size: coverSize, rotation: rotation)
        return CGRect(x: frame.minX + margin, y: frame.minY + margin, width: coverSize, height: coverSize)
    }

    /// Moves, resizes, and turns the cover in one step.
    public func setCover(frame cover: CGRect, rotation: CGFloat) {
        self.rotation = rotation
        coverSize = cover.width
        albumView.coverSide = coverSize
        albumView.rotation = rotation
        setFrame(Self.windowFrame(cover: cover, rotation: rotation), display: true)
        invalidateShadow()
    }

    /// The cover's square grown by its turn's margin on every side, so it stays centered.
    static func windowFrame(cover: CGRect, rotation: CGFloat) -> CGRect {
        let margin = Placement.rotationMargin(size: cover.width, rotation: rotation)
        return cover.insetBy(dx: -margin, dy: -margin)
    }
}
