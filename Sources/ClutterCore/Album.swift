public struct Album: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let spotifyURI: String
    /// Base name of the JPEG in Resources/Artwork (and in the app bundle).
    public let artworkName: String
}

extension Album {
    public static let all: [Album] = [
        Album(title: "The Singer in My Band", artist: "This Is Lorelei", spotifyURI: "spotify:album:24cxezS5U9YTFapgKpYG16", artworkName: "the-singer-in-my-band"),
        Album(title: "Hovvdy", artist: "Hovvdy", spotifyURI: "spotify:album:1jEwzUBvIlVPeOfqR3Ghr0", artworkName: "hovvdy"),
        Album(title: "Court and Spark", artist: "Joni Mitchell", spotifyURI: "spotify:album:2akjxkzFolkeV72Yyv5KrM", artworkName: "court-and-spark"),
        Album(title: "It Goes On", artist: "Westside Cowboy", spotifyURI: "spotify:album:3dWKCKeiWtxjDNPTbGCQTO", artworkName: "it-goes-on"),
        Album(title: "Lucifer on the Sofa", artist: "Spoon", spotifyURI: "spotify:album:1szMY4QqnQZgNuyLBC4jUQ", artworkName: "lucifer-on-the-sofa"),
        Album(title: "Punching the Clown", artist: "Lambchop", spotifyURI: "spotify:album:6ZZiqP4T7teY9nwGxlkSTz", artworkName: "punching-the-clown"),
    ]
}
