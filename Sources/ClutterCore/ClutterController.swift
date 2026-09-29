import AppKit

/// Shows a window for each album in the library, stacked in the library's order, and keeps the
/// saved library in step as covers are moved, clicked to the front, and replaced by `apply`.
@MainActor
public final class ClutterController: NSObject, NSWindowDelegate {
    public private(set) var library: Library
    public private(set) var coverSize: CoverSize
    public private(set) var showsInfoOnHover: Bool
    /// In stacking order, back to front, matching `library.entries`.
    public private(set) var windows: [AlbumWindow] = []
    /// Called after a cover's Remove button closes it, to take the album out of the Spotify library.
    public var onRemoveAlbum: ((Album) -> Void)?
    /// Whether the covers are hidden from the desktop; while they are, nothing orders a cover front.
    public private(set) var isHidden = false
    /// Albums whose covers were removed and whose removal from Spotify hasn't finished; `apply` leaves them out.
    private var removing: Set<String> = []

    /// Whether the topmost ordinary window on screen is one of ours; injectable for tests.
    var coversAreInFront: () -> Bool = { WindowStack.topWindowBelongs(toProcess: ProcessInfo.processInfo.processIdentifier) }

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
        coverSize: CoverSize = .medium,
        showsInfoOnHover: Bool = true,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.store = store
        self.artwork = artwork
        self.player = player
        self.screens = screens
        self.coverSize = coverSize
        self.showsInfoOnHover = showsInfoOnHover
        self.rng = rng
        self.library = Library()
        super.init()

        var library = store.load() ?? Library()
        // Starter albums from older versions were named by slug rather than Spotify ID; drop them.
        let current = library.entries.filter { "spotify:album:" + $0.album.artworkName == $0.album.spotifyURI }
        var changed = current.count != library.entries.count
        library = Library(entries: current)
        for entry in library.entries where !Placement.isVisible(frame(at: entry.origin), on: screens) {
            library.move(spotifyURI: entry.album.spotifyURI, to: randomOrigin())
            changed = true
        }
        self.library = library
        if changed { store.save(library) }
        windows = library.entries.map(makeWindow(for:))
    }

    /// Orders every cover front in stacking order, so the last is frontmost.
    public func showWindows() {
        windows.forEach(orderFront)
    }

    /// Hides or shows every cover. Covers added while hidden appear when they're shown again.
    public func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            windows.forEach { $0.orderOut(nil) }
        } else {
            showWindows()
        }
    }

    /// Hides the covers if they're showing in front, shows them if they're hidden, and brings them
    /// to the front if they're showing behind other apps' windows.
    public func toggle() {
        if isHidden {
            setHidden(false)
        } else if !windows.isEmpty, !coversAreInFront() {
            showWindows()
        } else {
            setHidden(true)
        }
    }

    private func orderFront(_ window: AlbumWindow) {
        if !isHidden { window.orderFrontRegardless() }
    }

    /// Resizes every cover to `size`, keeping each one's top-left corner where it is.
    public func setCoverSize(_ size: CoverSize) {
        coverSize = size
        for window in windows {
            let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
            let origin = CGPoint(x: topLeft.x, y: topLeft.y - size.points)
            window.setFrame(frame(at: origin), display: true)
            library.move(spotifyURI: window.album.spotifyURI, to: origin)
        }
        store.save(library)
    }

    /// Lines every cover up in a grid, each as near as it can get to where it was.
    public func tidy() {
        let origins = Placement.tidyOrigins(of: windows.map(\.frame.origin), size: coverSize.points, on: screens)
        place(origins)
    }

    /// Moves every cover to a new random spot, leaving the stacking order alone.
    public func scramble() {
        place(windows.map { _ in randomOrigin() })
    }

    /// Moves each cover to the matching origin, in stacking order, and saves the positions.
    private func place(_ origins: [CGPoint]) {
        for (window, origin) in zip(windows, origins) {
            window.setFrame(frame(at: origin), display: true)
            library.move(spotifyURI: window.album.spotifyURI, to: origin)
        }
        store.save(library)
    }

    /// Turns the artist-and-title hover overlay on or off for every cover.
    public func setShowsInfoOnHover(_ showsInfo: Bool) {
        showsInfoOnHover = showsInfo
        windows.forEach { $0.albumView.showsInfoOnHover = showsInfo }
    }

    /// Shows exactly `albums` (newest first): covers already shown stay where they are, neither moved
    /// nor reordered; the rest leave, and new ones appear at random spots above everything else, newest highest.
    /// A cover whose album details changed is rebuilt in place; a placeholder cover takes artwork cached since.
    /// Albums still being removed are left out.
    public func apply(_ albums: [Album]) {
        library.reconcile(with: albums.filter { !removing.contains($0.spotifyURI) }, newOrigin: randomOrigin)
        store.save(library)
        let old = windows
        var candidates = Dictionary(old.map { ($0.album.spotifyURI, $0) }, uniquingKeysWith: { first, _ in first })
        var reused = Set<ObjectIdentifier>()
        windows = library.entries.map { entry in
            if let window = candidates[entry.album.spotifyURI], window.album == entry.album {
                candidates[entry.album.spotifyURI] = nil
                reused.insert(ObjectIdentifier(window))
                if window.albumView.image == nil {
                    window.albumView.image = artwork.image(for: entry.album)
                }
                return window
            }
            return makeWindow(for: entry)
        }
        old.filter { !reused.contains(ObjectIdentifier($0)) }.forEach(close)
        // Only new covers come forward; the rest stay wherever they are among other apps' windows.
        windows.filter { !reused.contains(ObjectIdentifier($0)) }.forEach(orderFront)
    }

    /// Brings the album's cover to the front, showing the covers first if they were hidden.
    public func bringToFront(spotifyURI: String) {
        guard let window = windows.first(where: { $0.album.spotifyURI == spotifyURI }) else { return }
        setHidden(false)
        window.orderFrontRegardless()
        moveToFront(window)
    }

    /// Closes the album's cover and keeps it off the desktop until `finishRemoving` is called.
    public func remove(_ album: Album) {
        removing.insert(album.spotifyURI)
        library.remove(spotifyURI: album.spotifyURI)
        store.save(library)
        windows.removeAll { window in
            guard window.album.spotifyURI == album.spotifyURI else { return false }
            close(window)
            return true
        }
    }

    /// Lets `apply` show the album again, whether or not removing it from Spotify worked.
    public func finishRemoving(spotifyURI: String) {
        removing.remove(spotifyURI)
    }

    public func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? AlbumWindow else { return }
        library.move(spotifyURI: window.album.spotifyURI, to: window.frame.origin)
        store.save(library)
    }

    private func moveToFront(_ window: AlbumWindow) {
        guard let index = windows.firstIndex(where: { $0 === window }), index != windows.count - 1 else { return }
        windows.append(windows.remove(at: index))
        library.bringToFront(spotifyURI: window.album.spotifyURI)
        store.save(library)
    }

    private func close(_ window: AlbumWindow) {
        window.delegate = nil
        window.close()
    }

    private func makeWindow(for entry: Library.Entry) -> AlbumWindow {
        let album = entry.album
        let window = AlbumWindow(album: album, image: artwork.image(for: album), frame: frame(at: entry.origin))
        window.albumView.showsInfoOnHover = showsInfoOnHover
        window.albumView.onDoubleClick = { [player] in player.play(album) }
        window.albumView.onMouseDown = { [weak self, weak window] in
            if let self, let window { self.moveToFront(window) }
        }
        window.albumView.onRemove = { [weak self] in
            guard let self else { return }
            self.remove(album)
            self.onRemoveAlbum?(album)
        }
        window.delegate = self
        return window
    }

    private func randomOrigin() -> CGPoint {
        // Whole points, rounded down: AppKit snaps window frames to pixels, so a fractional origin
        // would be saved differently from where the window actually sits.
        let origin = Placement.randomOrigin(size: coverSize.points, in: screens[0], using: &rng)
        return CGPoint(x: origin.x.rounded(.down), y: origin.y.rounded(.down))
    }

    private func frame(at origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: CGSize(width: coverSize.points, height: coverSize.points))
    }
}
