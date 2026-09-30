public struct Album: Codable, Equatable, Sendable {
    public let title: String
    public let artist: String
    /// Identifies the album: a Spotify album URI, or a `SwinsianAlbum` URI.
    public let uri: String
    /// Base name of the cached cover JPEG: the Spotify album ID, or the Swinsian album's key.
    public let artworkName: String

    public init(title: String, artist: String, uri: String, artworkName: String) {
        self.title = title
        self.artist = artist
        self.uri = uri
        self.artworkName = artworkName
    }

    /// Saved libraries name the URI `spotifyURI`, from before albums could come from Swinsian.
    enum CodingKeys: String, CodingKey {
        case title, artist, artworkName
        case uri = "spotifyURI"
    }
}
