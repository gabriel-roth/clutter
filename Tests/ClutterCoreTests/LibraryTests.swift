import Foundation
import Testing
@testable import ClutterCore

private func album(_ id: String, title: String? = nil) -> Album {
    Album(title: title ?? "Title \(id)", artist: "Artist", spotifyURI: "spotify:album:\(id)", artworkName: id)
}
private let lorelei = album("lorelei")
private let hovvdy = album("hovvdy")
private let a = album("a"), b = album("b"), c = album("c"), d = album("d")

/// Hands out (0,0), (1,1), (2,2)… so tests can see which new album got which origin.
private func counter() -> () -> CGPoint {
    var n: CGFloat = 0
    return { defer { n += 1 }; return CGPoint(x: n, y: n) }
}

@Test func moveUpdatesTheOrigin() {
    var library = Library(entries: [.init(album: lorelei, origin: .zero)])
    library.move(spotifyURI: lorelei.spotifyURI, to: CGPoint(x: 300, y: 400))
    #expect(library.entries[0].origin == CGPoint(x: 300, y: 400))
}

@Test func moveOfAnUnknownAlbumChangesNothing() {
    var library = Library(entries: [.init(album: lorelei, origin: .zero)])
    library.move(spotifyURI: hovvdy.spotifyURI, to: CGPoint(x: 1, y: 1))
    #expect(library.entries == [Library.Entry(album: lorelei, origin: .zero)])
}

@Test func libraryRoundTripsThroughJSON() throws {
    let library = Library(entries: [
        .init(album: lorelei, origin: CGPoint(x: 12.5, y: 99)),
        .init(album: hovvdy, origin: CGPoint(x: -40, y: 7)),
    ])
    let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
    #expect(decoded == library)
}

@Test func reconcileKeepsSurvivorsInPlaceAndOrderAndStacksNewOnesNewestOnTop() {
    var library = Library(entries: [
        .init(album: b, origin: CGPoint(x: 50, y: 60)),
        .init(album: a, origin: CGPoint(x: 10, y: 20)),
    ])
    // Newest first: d, then c, then a and b already shown.
    library.reconcile(with: [d, c, a, b], newOrigin: counter())
    #expect(library.entries == [
        .init(album: b, origin: CGPoint(x: 50, y: 60)),
        .init(album: a, origin: CGPoint(x: 10, y: 20)),
        .init(album: c, origin: CGPoint(x: 0, y: 0)),
        .init(album: d, origin: CGPoint(x: 1, y: 1)),
    ])
}

@Test func reconcileDropsAlbumsThatAreNoLongerWanted() {
    var library = Library(entries: [.init(album: a, origin: .zero), .init(album: b, origin: .zero)])
    library.reconcile(with: [b], newOrigin: counter())
    #expect(library.entries.map(\.album) == [b])
}

@Test func reconcileWithNothingEmptiesTheLibrary() {
    var library = Library(entries: [.init(album: a, origin: .zero)])
    library.reconcile(with: [], newOrigin: counter())
    #expect(library.entries.isEmpty)
}

@Test func reconcileOfAnEmptyLibraryAddsEverythingOldestFirst() {
    var library = Library()
    library.reconcile(with: [c, b, a], newOrigin: counter())
    #expect(library.entries.map(\.album) == [a, b, c])
}

@Test func reconcileUpdatesASurvivorsDetails() {
    var library = Library(entries: [.init(album: a, origin: CGPoint(x: 5, y: 5))])
    let renamed = album("a", title: "New Title")
    library.reconcile(with: [renamed], newOrigin: counter())
    #expect(library.entries == [.init(album: renamed, origin: CGPoint(x: 5, y: 5))])
}

@Test func reconcileShowsADuplicatedAlbumOnce() {
    var library = Library()
    library.reconcile(with: [a, b, a], newOrigin: counter())
    // Newest first, so walking oldest to newest meets the last `a`, then `b`, then skips the first `a`.
    #expect(library.entries.map(\.album) == [a, b])
}

@Test func bringToFrontMovesTheEntryToTheEnd() {
    var library = Library(entries: [.init(album: a, origin: .zero), .init(album: b, origin: .zero), .init(album: c, origin: .zero)])
    library.bringToFront(spotifyURI: a.spotifyURI)
    #expect(library.entries.map(\.album) == [b, c, a])
}

@Test func bringToFrontOfAnUnknownAlbumChangesNothing() {
    var library = Library(entries: [.init(album: a, origin: .zero)])
    library.bringToFront(spotifyURI: d.spotifyURI)
    #expect(library.entries.map(\.album) == [a])
}
