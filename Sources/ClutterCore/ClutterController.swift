import AppKit

/// Creates a cover window for each album and wires double-clicks to playback.
@MainActor
public final class ClutterController {
    public static let windowSize: CGFloat = 220

    public let windows: [AlbumWindow]

    public init(albums: [Album], player: SpotifyPlayer, visibleFrame: CGRect, image: (Album) -> NSImage?) {
        let frames = WindowLayout.frames(count: albums.count, size: Self.windowSize, in: visibleFrame)
        windows = zip(albums, frames).map { album, frame in
            let window = AlbumWindow(album: album, image: image(album), frame: frame)
            window.albumView.onDoubleClick = { player.play(album) }
            return window
        }
    }

    public func showWindows() {
        windows.forEach { $0.orderFront(nil) }
    }
}
