import CoreGraphics

/// The albums on the desktop and where each cover sits. Albums are identified by Spotify URI.
public struct Library: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var album: Album
        /// Bottom-left corner of the cover's window, in screen coordinates.
        public var origin: CGPoint

        public init(album: Album, origin: CGPoint) {
            self.album = album
            self.origin = origin
        }
    }

    /// Back-to-front stacking order: the last entry is the frontmost cover.
    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public func contains(spotifyURI: String) -> Bool {
        entries.contains { $0.album.spotifyURI == spotifyURI }
    }

    /// Returns false, changing nothing, if the album is already in the library.
    @discardableResult
    public mutating func add(_ album: Album, at origin: CGPoint) -> Bool {
        guard !contains(spotifyURI: album.spotifyURI) else { return false }
        entries.append(Entry(album: album, origin: origin))
        return true
    }

    public mutating func remove(spotifyURI: String) {
        entries.removeAll { $0.album.spotifyURI == spotifyURI }
    }

    public mutating func move(spotifyURI: String, to origin: CGPoint) {
        guard let index = entries.firstIndex(where: { $0.album.spotifyURI == spotifyURI }) else { return }
        entries[index].origin = origin
    }

    /// Makes the library show exactly `albums` (newest first). Albums already shown keep their
    /// origin and stacking order, taking any updated details. New ones are stacked on top, oldest
    /// first so the newest ends up frontmost, each at `newOrigin()`.
    public mutating func reconcile(with albums: [Album], newOrigin: () -> CGPoint) {
        let wanted = Dictionary(albums.map { ($0.spotifyURI, $0) }, uniquingKeysWith: { first, _ in first })
        entries = entries.compactMap { entry in
            wanted[entry.album.spotifyURI].map { Entry(album: $0, origin: entry.origin) }
        }
        for album in albums.reversed() where !contains(spotifyURI: album.spotifyURI) {
            entries.append(Entry(album: album, origin: newOrigin()))
        }
    }

    public mutating func bringToFront(spotifyURI: String) {
        guard let index = entries.firstIndex(where: { $0.album.spotifyURI == spotifyURI }) else { return }
        entries.append(entries.remove(at: index))
    }
}
