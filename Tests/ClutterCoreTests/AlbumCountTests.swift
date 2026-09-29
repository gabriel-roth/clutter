import Foundation
import Testing
@testable import ClutterCore

@Test func albumCountDefaultsToTen() {
    #expect(AlbumCount.saved(in: freshDefaults()) == 10)
    #expect(AlbumCount.range == 1...100)
}

@Test func savedAlbumCountLoadsBack() {
    let defaults = freshDefaults()
    AlbumCount.save(37, in: defaults)
    #expect(AlbumCount.saved(in: defaults) == 37)
}

@Test(arguments: [(0, 1), (-5, 1), (101, 100), (5000, 100), (1, 1), (100, 100)])
func albumCountIsClampedToItsRange(stored: Int, expected: Int) {
    let defaults = freshDefaults()
    defaults.set(stored, forKey: AlbumCount.defaultsKey)
    #expect(AlbumCount.saved(in: defaults) == expected)
    AlbumCount.save(stored, in: defaults)
    #expect(defaults.integer(forKey: AlbumCount.defaultsKey) == expected)
}
