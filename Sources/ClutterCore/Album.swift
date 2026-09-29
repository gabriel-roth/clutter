public struct Album: Codable, Equatable, Sendable {
    public let title: String
    public let artist: String
    public let spotifyURI: String
    /// Base name of the cached cover JPEG: the Spotify album ID.
    public let artworkName: String

    public init(title: String, artist: String, spotifyURI: String, artworkName: String) {
        self.title = title
        self.artist = artist
        self.spotifyURI = spotifyURI
        self.artworkName = artworkName
    }
}
