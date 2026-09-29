import CoreGraphics
import Testing
@testable import ClutterCore

@Test func laysOutARowFromTheTopLeft() {
    let screen = CGRect(x: 0, y: 0, width: 2000, height: 1000)
    let frames = WindowLayout.frames(count: 3, size: 100, in: screen)
    #expect(frames == [
        CGRect(x: 40, y: 860, width: 100, height: 100),
        CGRect(x: 160, y: 860, width: 100, height: 100),
        CGRect(x: 280, y: 860, width: 100, height: 100),
    ])
}

@Test func wrapsToANewRowWhenTheScreenIsFull() {
    // 40 + 100 + 20 + 100 + 40 = 300 fits exactly two per row.
    let screen = CGRect(x: 0, y: 0, width: 300, height: 1000)
    let frames = WindowLayout.frames(count: 3, size: 100, in: screen)
    #expect(frames[1] == CGRect(x: 160, y: 860, width: 100, height: 100))
    #expect(frames[2] == CGRect(x: 40, y: 740, width: 100, height: 100))
}

@Test func respectsTheVisibleFrameOrigin() {
    let screen = CGRect(x: 1440, y: 25, width: 1000, height: 800)
    #expect(WindowLayout.frames(count: 1, size: 100, in: screen)
        == [CGRect(x: 1480, y: 685, width: 100, height: 100)])
}

@Test func tinyScreenStillPutsOneWindowPerRow() {
    let screen = CGRect(x: 0, y: 0, width: 50, height: 1000)
    let frames = WindowLayout.frames(count: 2, size: 100, in: screen)
    #expect(frames.map(\.minX) == [40, 40])
    #expect(frames.map(\.minY) == [860, 740])
}
