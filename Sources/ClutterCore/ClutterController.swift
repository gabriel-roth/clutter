import AppKit

/// Shows a window for each album in the library and keeps the saved library in step
/// as covers are moved, closed, and added.
@MainActor
public final class ClutterController: NSObject, NSWindowDelegate {
    public nonisolated static let windowSize: CGFloat = 220

    public private(set) var library: Library
    public private(set) var windows: [AlbumWindow] = []

    private let store: LibraryStore
    private let artwork: ArtworkStore
    private let player: SpotifyPlayer
    private let screens: [CGRect]
    private var rng: any RandomNumberGenerator

    /// `screens` are the screens' visible frames, main screen first; new covers go on the first.
    public init(
        store: LibraryStore,
        artwork: ArtworkStore,
        player: SpotifyPlayer,
        screens: [CGRect],
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.store = store
        self.artwork = artwork
        self.player = player
        self.screens = screens
        self.rng = rng
        self.library = Library()
        super.init()

        let saved = store.load()
        var library = saved ?? Library()
        var changed = saved == nil
        if saved == nil {
            for album in Album.starters {
                library.add(album, at: randomOrigin())
            }
        }
        for entry in library.entries where !Placement.isVisible(Self.frame(at: entry.origin), on: screens) {
            library.move(spotifyURI: entry.album.spotifyURI, to: randomOrigin())
            changed = true
        }
        self.library = library
        if changed { store.save(library) }
        windows = library.entries.map(makeWindow(for:))
    }

    public func showWindows() {
        windows.forEach { $0.orderFront(nil) }
    }

    /// Shows a new cover for `album` at a random spot. If it's already shown, brings that cover
    /// to the front instead and returns false.
    @discardableResult
    public func add(_ album: Album) -> Bool {
        if let existing = windows.first(where: { $0.album.spotifyURI == album.spotifyURI }) {
            existing.orderFrontRegardless()
            return false
        }
        let entry = Library.Entry(album: album, origin: randomOrigin())
        library.add(album, at: entry.origin)
        store.save(library)
        let window = makeWindow(for: entry)
        windows.append(window)
        window.orderFrontRegardless()
        return true
    }

    public func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? AlbumWindow else { return }
        library.move(spotifyURI: window.album.spotifyURI, to: window.frame.origin)
        store.save(library)
    }

    private func remove(_ album: Album) {
        library.remove(spotifyURI: album.spotifyURI)
        store.save(library)
        guard let index = windows.firstIndex(where: { $0.album.spotifyURI == album.spotifyURI }) else { return }
        let window = windows.remove(at: index)
        window.delegate = nil
        window.close()
    }

    private func makeWindow(for entry: Library.Entry) -> AlbumWindow {
        let album = entry.album
        let window = AlbumWindow(album: album, image: artwork.image(for: album), frame: Self.frame(at: entry.origin))
        window.albumView.onDoubleClick = { [player] in player.play(album) }
        window.albumView.onClose = { [weak self] in self?.remove(album) }
        window.delegate = self
        return window
    }

    private func randomOrigin() -> CGPoint {
        // Whole points, rounded down: AppKit snaps window frames to pixels, so a fractional origin
        // would be saved differently from where the window actually sits.
        let origin = Placement.randomOrigin(size: Self.windowSize, in: screens[0], using: &rng)
        return CGPoint(x: origin.x.rounded(.down), y: origin.y.rounded(.down))
    }

    private static func frame(at origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: CGSize(width: windowSize, height: windowSize))
    }
}
