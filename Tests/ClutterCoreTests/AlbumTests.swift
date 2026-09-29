import Foundation
import Testing
@testable import ClutterCore

@Test func catalogHasTheSixAlbumsInOrder() {
    #expect(Album.starters.map(\.title) == [
        "The Singer in My Band", "Hovvdy", "Court and Spark",
        "It Goes On", "Lucifer on the Sofa", "Punching the Clown",
    ])
    #expect(Album.starters.map(\.spotifyURI) == [
        "spotify:album:24cxezS5U9YTFapgKpYG16", "spotify:album:1jEwzUBvIlVPeOfqR3Ghr0",
        "spotify:album:2akjxkzFolkeV72Yyv5KrM", "spotify:album:3dWKCKeiWtxjDNPTbGCQTO",
        "spotify:album:1szMY4QqnQZgNuyLBC4jUQ", "spotify:album:6ZZiqP4T7teY9nwGxlkSTz",
    ])
}

@Test func everyAlbumHasArtworkInTheRepo() {
    let artwork = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Resources/Artwork")
    for album in Album.starters {
        let file = artwork.appending(path: "\(album.artworkName).jpg")
        #expect(FileManager.default.fileExists(atPath: file.path), "missing \(file.path)")
    }
}
