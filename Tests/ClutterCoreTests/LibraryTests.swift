import Foundation
import Testing
@testable import ClutterCore

private let lorelei = Album.starters[0]
private let hovvdy = Album.starters[1]

@Test func addAppendsTheAlbumAtItsOrigin() {
    var library = Library()
    let added = library.add(lorelei, at: CGPoint(x: 10, y: 20))
    #expect(added)
    #expect(library.entries == [Library.Entry(album: lorelei, origin: CGPoint(x: 10, y: 20))])
    #expect(library.contains(spotifyURI: lorelei.spotifyURI))
}

@Test func addRefusesAnAlbumThatIsAlreadyThere() {
    var library = Library()
    library.add(lorelei, at: .zero)
    let addedAgain = library.add(lorelei, at: CGPoint(x: 5, y: 5))
    #expect(!addedAgain)
    #expect(library.entries.count == 1)
    #expect(library.entries[0].origin == .zero)
}

@Test func removeDropsTheAlbum() {
    var library = Library()
    library.add(lorelei, at: .zero)
    library.add(hovvdy, at: .zero)
    library.remove(spotifyURI: lorelei.spotifyURI)
    #expect(library.entries.map(\.album) == [hovvdy])
    #expect(!library.contains(spotifyURI: lorelei.spotifyURI))
}

@Test func moveUpdatesTheOrigin() {
    var library = Library()
    library.add(lorelei, at: .zero)
    library.move(spotifyURI: lorelei.spotifyURI, to: CGPoint(x: 300, y: 400))
    #expect(library.entries[0].origin == CGPoint(x: 300, y: 400))
}

@Test func moveOfAnUnknownAlbumChangesNothing() {
    var library = Library()
    library.add(lorelei, at: .zero)
    library.move(spotifyURI: hovvdy.spotifyURI, to: CGPoint(x: 1, y: 1))
    #expect(library.entries == [Library.Entry(album: lorelei, origin: .zero)])
}

@Test func libraryRoundTripsThroughJSON() throws {
    var library = Library()
    library.add(lorelei, at: CGPoint(x: 12.5, y: 99))
    library.add(hovvdy, at: CGPoint(x: -40, y: 7))
    let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
    #expect(decoded == library)
}
