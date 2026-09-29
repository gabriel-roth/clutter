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

@Test func tidyCentersASingleCover() {
    #expect(tidied([CGPoint(x: 3, y: 30)]) == [CGPoint(x: 610, y: 352)])
}

@Test func tidyPutsFourCoversInATwoByTwoGridNearestTheirOldSpots() {
    let result = tidied([CGPoint(x: 70, y: 40), CGPoint(x: 900, y: 60), CGPoint(x: 90, y: 600), CGPoint(x: 850, y: 700)])
    #expect(result == [CGPoint(x: 333, y: 170), CGPoint(x: 886, y: 170), CGPoint(x: 333, y: 535), CGPoint(x: 886, y: 535)])
}

@Test func tidySpreadsCoversWithEqualGapsAndMargins() {
    let result = tidied(Array(repeating: CGPoint(x: 400, y: 300), count: 10)) // a five-by-two grid
    let xs = Array(Set(result.map(\.x))).sorted()
    let ys = Array(Set(result.map(\.y))).sorted()
    #expect(xs.count == 5 && ys.count == 2)
    let xGaps = [xs[0] - screen.minX] + zip(xs, xs.dropFirst()).map { $1 - $0 - 220 } + [screen.maxX - xs[4] - 220]
    let yGaps = [ys[0] - screen.minY] + zip(ys, ys.dropFirst()).map { $1 - $0 - 220 } + [screen.maxY - ys[1] - 220]
    #expect(xGaps.max()! - xGaps.min()! <= 1)
    #expect(yGaps.max()! - yGaps.min()! <= 1)
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

// MARK: Scramble

private func scrambled(count: Int, seed: UInt64, size: CGFloat = 220) -> [Placement.Spot] {
    var rng = SeededGenerator(seed: seed)
    return Placement.scrambledSpots(count: count, size: size, in: screen, using: &rng)
}

@Test func scrambleKeepsEveryTurnedCoverOnScreen() {
    for seed in 0..<200 as Range<UInt64> {
        for spot in scrambled(count: 10, seed: seed) {
            let margin = Placement.rotationMargin(size: 220, rotation: spot.rotation)
            let box = CGRect(origin: spot.origin, size: CGSize(width: 220, height: 220)).insetBy(dx: -margin, dy: -margin)
            #expect(screen.contains(box), "\(box) is not inside \(screen)")
        }
    }
}

@Test func scrambleSpreadsCoversAcrossTheWholeScreen() {
    for seed in 0..<100 as Range<UInt64> {
        let origins = scrambled(count: 10, seed: seed).map(\.origin)
        #expect(origins.map(\.x).min()! < 400 && origins.map(\.x).max()! > 800)
        #expect(origins.map(\.y).min()! < 300 && origins.map(\.y).max()! > 400)
    }
}

@Test func scrambleDoesNotLineCoversUpInRowsOrColumns() {
    let origins = scrambled(count: 10, seed: 5).map(\.origin)
    #expect(Set(origins.map(\.x)).count >= 8)
    #expect(Set(origins.map(\.y)).count >= 8)
}

@Test func scrambleTurnsSomeCoversAndLeavesOthersStraight() {
    let rotations = (0..<50 as Range<UInt64>).flatMap { seed in scrambled(count: 10, seed: seed).map(\.rotation) }
    #expect(rotations.allSatisfy { abs($0) <= 15 })
    #expect(rotations.contains { $0 > 10 } && rotations.contains { $0 < -10 })
    #expect(rotations.contains(0) && rotations.contains { $0 != 0 })
}

@Test func scrambleIsDifferentEachTime() {
    #expect(scrambled(count: 10, seed: 1) != scrambled(count: 10, seed: 2))
}

@Test func scrambleOfNothingIsNothing() {
    #expect(scrambled(count: 0, seed: 1).isEmpty)
}

private func manyRotations() -> [CGFloat] {
    var rng = SeededGenerator(seed: 9)
    return (0..<20_000).map { _ in Placement.randomRotation(using: &rng) }
}

@Test func randomRotationsStayWithinFifteenDegreesEitherWay() {
    let rotations = manyRotations()
    #expect(rotations.allSatisfy { abs($0) <= 15 })
    #expect(rotations.contains { $0 > 14 } && rotations.contains { $0 < -14 })
}

@Test func fortyPercentOfRandomRotationsAreStraight() {
    let straight = Double(manyRotations().filter { $0 == 0 }.count) / 20_000
    #expect(abs(straight - 0.4) < 0.02, "\(straight) of the covers were straight")
}

@Test func turnedCoversAreTurnedAtLeastAVisibleAmountAndBothWays() {
    let turned = manyRotations().filter { $0 != 0 }
    #expect(turned.allSatisfy { abs($0) >= 1 })
    let clockwise = Double(turned.filter { $0 < 0 }.count) / Double(turned.count)
    #expect(abs(clockwise - 0.5) < 0.03)
}

@Test func smallerTurnsAreLikelierThanLargerOnes() {
    let sizes = manyRotations().map(abs).filter { $0 != 0 }
    let bands = [1.0..<4, 4..<8, 8..<12, 12..<15.1].map { band in sizes.filter { band.contains(Double($0)) }.count }
    #expect(bands[0] > bands[1] && bands[1] > bands[2] && bands[2] > bands[3], "\(bands)")
}

@Test func aTurnedCoverNeedsRoomAroundItsSquare() {
    #expect(Placement.rotationMargin(size: 220, rotation: 0) == 0)
    #expect(Placement.rotationMargin(size: 220, rotation: 15) == 25)
    #expect(Placement.rotationMargin(size: 220, rotation: -15) == 25)
    #expect(Placement.rotationMargin(size: 220, rotation: 0.1) >= 1)
}
