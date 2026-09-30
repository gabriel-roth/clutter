@MainActor
public protocol AlbumPlayer {
    func play(_ album: Album)
}

/// Plays Swinsian albums in Swinsian and the rest in Spotify.
public struct RoutingPlayer: AlbumPlayer {
    private let spotify: any AlbumPlayer
    private let swinsian: any AlbumPlayer

    public init(spotify: any AlbumPlayer, swinsian: any AlbumPlayer) {
        self.spotify = spotify
        self.swinsian = swinsian
    }

    public func play(_ album: Album) {
        (SwinsianAlbum.isSwinsian(album) ? swinsian : spotify).play(album)
    }
}
