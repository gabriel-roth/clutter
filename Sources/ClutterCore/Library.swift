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
}
