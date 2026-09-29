import CoreGraphics

/// The albums on the desktop and where each cover sits. Albums are identified by Spotify URI.
public struct Library: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var album: Album
        /// Bottom-left corner of the cover's window, in screen coordinates.
        public var origin: CGPoint
        /// How far the cover is turned, in degrees counterclockwise, about its center.
        public var rotation: CGFloat

        public init(album: Album, origin: CGPoint, rotation: CGFloat = 0) {
            self.album = album
            self.origin = origin
            self.rotation = rotation
        }

        /// Libraries saved before covers could turn have no rotation.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            album = try container.decode(Album.self, forKey: .album)
            origin = try container.decode(CGPoint.self, forKey: .origin)
            rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
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

    public mutating func move(spotifyURI: String, to origin: CGPoint) {
        guard let index = entries.firstIndex(where: { $0.album.spotifyURI == spotifyURI }) else { return }
        entries[index].origin = origin
    }

    /// Moves the cover and sets how far it's turned.
    public mutating func place(spotifyURI: String, at origin: CGPoint, rotation: CGFloat) {
        guard let index = entries.firstIndex(where: { $0.album.spotifyURI == spotifyURI }) else { return }
        entries[index].origin = origin
        entries[index].rotation = rotation
    }

    /// Makes the library show exactly `albums` (newest first). Albums already shown keep their
    /// origin and stacking order, taking any updated details. New ones are stacked on top, oldest
    /// first so the newest ends up frontmost, each at `newOrigin()`, turned by `newRotation()`.
    public mutating func reconcile(with albums: [Album], newOrigin: () -> CGPoint, newRotation: () -> CGFloat = { 0 }) {
        let wanted = Dictionary(albums.map { ($0.spotifyURI, $0) }, uniquingKeysWith: { first, _ in first })
        entries = entries.compactMap { entry in
            wanted[entry.album.spotifyURI].map { Entry(album: $0, origin: entry.origin, rotation: entry.rotation) }
        }
        for album in albums.reversed() where !contains(spotifyURI: album.spotifyURI) {
            entries.append(Entry(album: album, origin: newOrigin(), rotation: newRotation()))
        }
    }

    public mutating func remove(spotifyURI: String) {
        entries.removeAll { $0.album.spotifyURI == spotifyURI }
    }

    public mutating func bringToFront(spotifyURI: String) {
        guard let index = entries.firstIndex(where: { $0.album.spotifyURI == spotifyURI }) else { return }
        entries.append(entries.remove(at: index))
    }
}
