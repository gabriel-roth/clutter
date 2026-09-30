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
    /// Called when `toggle` shows the covers, so the app can become active and take keystrokes such as Command-Comma.
    public var onShownByToggle: (() -> Void)?
    /// Whether the covers are hidden from the desktop; while they are, nothing orders a cover front.
    public private(set) var isHidden = false
    /// Albums whose covers were removed and whose removal from Spotify hasn't finished; `apply` leaves them out.
    private var removing: Set<String> = []

    /// Whether the topmost ordinary window on screen is one of ours; injectable for tests.
    var coversAreInFront: () -> Bool = { WindowStack.topWindowBelongs(toProcess: ProcessInfo.processInfo.processIdentifier) }

    private let store: LibraryStore
    private let artwork: ArtworkStore
    private let player: AlbumPlayer
    private let screens: [CGRect]
    private var rng: any RandomNumberGenerator

    /// `screens` are the screens' visible frames, main screen first; new covers go on the first.
    public init(
        store: LibraryStore,
        artwork: ArtworkStore,
        player: AlbumPlayer,
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
        let current = library.entries.filter { SwinsianAlbum.isSwinsian($0.album) || "spotify:album:" + $0.album.artworkName == $0.album.uri }
        var changed = current.count != library.entries.count
        library = Library(entries: current)
        for entry in library.entries where !Placement.isVisible(frame(at: entry.origin), on: screens) {
            let spot = randomSpot()
            library.place(uri: entry.album.uri, at: spot.origin, rotation: spot.rotation)
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
            takeFocus()
        } else if !windows.isEmpty, !coversAreInFront() {
            showWindows()
            takeFocus()
        } else {
            setHidden(true)
        }
    }

    /// Makes the app active with the frontmost cover as its key window.
    private func takeFocus() {
        onShownByToggle?()
        windows.last?.makeKey()
    }

    private func orderFront(_ window: AlbumWindow) {
        if !isHidden { window.orderFrontRegardless() }
    }

    /// Resizes every cover to `size`, keeping each one's top-left corner where it is.
    public func setCoverSize(_ size: CoverSize) {
        coverSize = size
        for window in windows {
            let cover = window.coverFrame
            let origin = CGPoint(x: cover.minX, y: cover.maxY - size.points)
            window.setCover(frame: frame(at: origin), rotation: window.rotation)
            library.move(uri: window.album.uri, to: origin)
        }
        store.save(library)
    }

    /// Lines every cover up in an evenly spread grid, each as near as it can get to where it was, and
    /// turns them all straight.
    public func tidy() {
        let origins = Placement.tidyOrigins(of: windows.map(\.coverFrame.origin), size: coverSize.points, on: screens)
        place(origins.map { Placement.Spot(origin: $0, rotation: 0) })
    }

    /// Moves every cover to a new messy spot spread across the first screen, turning each a little,
    /// and leaves the stacking order alone.
    public func scramble() {
        place(Placement.scrambledSpots(count: windows.count, size: coverSize.points, in: screens[0], using: &rng))
    }

    /// Moves and turns each cover, in stacking order, to the matching spot, and saves them.
    private func place(_ spots: [Placement.Spot]) {
        for (window, spot) in zip(windows, spots) {
            window.setCover(frame: frame(at: spot.origin), rotation: spot.rotation)
            library.place(uri: window.album.uri, at: spot.origin, rotation: spot.rotation)
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
        // A new cover's turn is chosen before its origin, which must leave room for the turn.
        var pending: Placement.Spot?
        library.reconcile(
            with: albums.filter { !removing.contains($0.uri) },
            newOrigin: { let spot = randomSpot(); pending = spot; return spot.origin },
            newRotation: { pending?.rotation ?? 0 }
        )
        store.save(library)
        let old = windows
        var candidates = Dictionary(old.map { ($0.album.uri, $0) }, uniquingKeysWith: { first, _ in first })
        var reused = Set<ObjectIdentifier>()
        windows = library.entries.map { entry in
            if let window = candidates[entry.album.uri], window.album == entry.album {
                candidates[entry.album.uri] = nil
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
    public func bringToFront(uri: String) {
        guard let window = windows.first(where: { $0.album.uri == uri }) else { return }
        setHidden(false)
        window.orderFrontRegardless()
        moveToFront(window)
    }

    /// Closes the album's cover and keeps it off the desktop until `finishRemoving` is called.
    public func remove(_ album: Album) {
        removing.insert(album.uri)
        library.remove(uri: album.uri)
        store.save(library)
        windows.removeAll { window in
            guard window.album.uri == album.uri else { return false }
            close(window)
            return true
        }
    }

    /// Lets `apply` show the album again, whether or not removing it from Spotify worked.
    public func finishRemoving(uri: String) {
        removing.remove(uri)
    }

    public func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? AlbumWindow else { return }
        library.move(uri: window.album.uri, to: window.coverFrame.origin)
        store.save(library)
    }

    private func moveToFront(_ window: AlbumWindow) {
        guard let index = windows.firstIndex(where: { $0 === window }), index != windows.count - 1 else { return }
        windows.append(windows.remove(at: index))
        library.bringToFront(uri: window.album.uri)
        store.save(library)
    }

    private func close(_ window: AlbumWindow) {
        window.delegate = nil
        window.close()
    }

    private func makeWindow(for entry: Library.Entry) -> AlbumWindow {
        let album = entry.album
        let window = AlbumWindow(album: album, image: artwork.image(for: album), frame: frame(at: entry.origin), rotation: entry.rotation)
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

    /// A random turn and, on the first screen, an origin that leaves the whole turned cover on screen.
    private func randomSpot() -> Placement.Spot {
        let rotation = Placement.randomRotation(using: &rng)
        let margin = Placement.rotationMargin(size: coverSize.points, rotation: rotation)
        // Whole points, rounded down: AppKit snaps window frames to pixels, so a fractional origin
        // would be saved differently from where the window actually sits.
        let origin = Placement.randomOrigin(size: coverSize.points, in: screens[0].insetBy(dx: margin, dy: margin), using: &rng)
        return Placement.Spot(origin: CGPoint(x: origin.x.rounded(.down), y: origin.y.rounded(.down)), rotation: rotation)
    }

    /// The cover's square at `origin`.
    private func frame(at origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: CGSize(width: coverSize.points, height: coverSize.points))
    }
}
