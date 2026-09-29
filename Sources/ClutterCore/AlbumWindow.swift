import AppKit

/// A borderless window that is nothing but an album cover.
public final class AlbumWindow: NSWindow {
    public let album: Album
    public let albumView: AlbumView

    public init(album: Album, image: NSImage?, frame: CGRect) {
        self.album = album
        self.albumView = AlbumView(image: image, artist: album.artist, title: album.title)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        contentView = albumView
        hasShadow = true
        isReleasedWhenClosed = false
        title = "\(album.title) — \(album.artist)"
    }

    public override var canBecomeKey: Bool { true }
}
