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
