import CoreGraphics
import Testing
@testable import ClutterCore

private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

@Test func randomOriginsKeepTheWholeCoverOnScreen() {
    var rng = SeededGenerator(seed: 42)
    for _ in 0..<1000 {
        let origin = Placement.randomOrigin(size: 220, in: screen, using: &rng)
        let frame = CGRect(origin: origin, size: CGSize(width: 220, height: 220))
        #expect(screen.contains(frame), "\(frame) is not inside \(screen)")
    }
}

@Test func randomOriginsAreScattered() {
    var rng = SeededGenerator(seed: 7)
    let origins = (0..<6).map { _ in Placement.randomOrigin(size: 220, in: screen, using: &rng) }
    #expect(Set(origins.map(\.x)).count == 6)
    #expect(Set(origins.map(\.y)).count == 6)
}

@Test func screenSmallerThanTheCoverPinsItToTheTopLeft() {
    var rng = SeededGenerator(seed: 1)
    let tiny = CGRect(x: 10, y: 20, width: 100, height: 100)
    #expect(Placement.randomOrigin(size: 220, in: tiny, using: &rng) == CGPoint(x: 10, y: -100))
}

@Test func frameOverlappingAScreenIsVisible() {
    let frame = CGRect(x: 1400, y: 500, width: 220, height: 220) // mostly off the right edge
    #expect(Placement.isVisible(frame, on: [screen]))
}

@Test func frameOnASecondScreenIsVisible() {
    let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    #expect(Placement.isVisible(CGRect(x: 2000, y: 300, width: 220, height: 220), on: [screen, second]))
}

@Test func frameOffEveryScreenIsNotVisible() {
    #expect(!Placement.isVisible(CGRect(x: 5000, y: 5000, width: 220, height: 220), on: [screen]))
}

// MARK: Tidy

private func tidied(_ origins: [CGPoint], size: CGFloat = 220, on screens: [CGRect] = [screen]) -> [CGPoint] {
    Placement.tidyOrigins(of: origins, size: size, on: screens)
}

@Test func tidyKeepsEachCoverInItsOwnCell() {
    // 1440 wide fits 6 columns of 220 (1320, leaving 120 of margin); 875 high fits 3 rows (660, leaving 215).
    let result = tidied([CGPoint(x: 3, y: 30), CGPoint(x: 1000, y: 700)])
    #expect(Set(result.map(\.x)).isSubset(of: (0..<6).map { 60 + CGFloat($0) * 220 }))
    #expect(Set(result.map(\.y)).isSubset(of: (0..<3).map { 25 + 107 + CGFloat($0) * 220 }))
    #expect(distinctCount(result) == 2)
}

@Test func tidyMovesACoverToTheNearestCell() {
    let result = tidied([CGPoint(x: 70, y: 40)])
    #expect(result == [CGPoint(x: 60, y: 132)])
}

@Test func tidyGivesEveryCoverADistinctCellEvenWhenTheyStartStacked() {
    let result = tidied(Array(repeating: CGPoint(x: 400, y: 300), count: 10))
    #expect(distinctCount(result) == 10)
    for origin in result {
        #expect(screen.contains(CGRect(origin: origin, size: CGSize(width: 220, height: 220))))
    }
}

@Test func tidyDoesNotCrossCoversThatAreAlreadyInOrder() {
    let result = tidied([CGPoint(x: 0, y: 300), CGPoint(x: 400, y: 300), CGPoint(x: 800, y: 300)])
    #expect(result[0].x < result[1].x && result[1].x < result[2].x)
    #expect(Set(result.map(\.y)).count == 1)
}

@Test func tidyIsIdempotent() {
    let once = tidied([CGPoint(x: 10, y: 50), CGPoint(x: 500, y: 90), CGPoint(x: 520, y: 400), CGPoint(x: 900, y: 700)])
    #expect(tidied(once) == once)
}

@Test func tidyUsesEveryScreen() {
    let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let result = tidied([CGPoint(x: 2000, y: 300), CGPoint(x: 100, y: 300)], on: [screen, second])
    #expect(second.contains(CGRect(origin: result[0], size: CGSize(width: 220, height: 220))))
    #expect(screen.contains(CGRect(origin: result[1], size: CGSize(width: 220, height: 220))))
}

@Test func tidyOverlapsWhenThereAreMoreCoversThanCells() {
    let result = tidied(Array(repeating: CGPoint(x: 400, y: 300), count: 40))
    #expect(distinctCount(result) == 40)
    for origin in result {
        #expect(screen.contains(CGRect(origin: origin, size: CGSize(width: 220, height: 220))))
    }
}

@Test func tidyOfNothingIsNothing() {
    #expect(tidied([]).isEmpty)
}

@Test func tidyOnAScreenSmallerThanACoverPinsToTheTopLeft() {
    let tiny = CGRect(x: 10, y: 20, width: 100, height: 100)
    #expect(tidied([CGPoint(x: 50, y: 50)], on: [tiny]) == [CGPoint(x: 10, y: -100)])
}

private func distinctCount(_ points: [CGPoint]) -> Int {
    Set(points.map { "\($0.x),\($0.y)" }).count
}
