import Foundation
import Testing
@testable import ClutterCore

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ClutterTests-\(UUID().uuidString)")!
}

@Test func coverSizesInPoints() {
    #expect(CoverSize.allCases == [.small, .medium, .large])
    #expect(CoverSize.allCases.map(\.points) == [160, 220, 300])
    #expect(CoverSize.allCases.map(\.title) == ["Small", "Medium", "Large"])
}

@Test func coverSizeDefaultsToMedium() {
    #expect(CoverSize.saved(in: freshDefaults()) == .medium)
}

@Test func savedCoverSizeLoadsBack() {
    let defaults = freshDefaults()
    CoverSize.large.save(in: defaults)
    #expect(CoverSize.saved(in: defaults) == .large)
}

@Test func unrecognizedSavedCoverSizeFallsBackToMedium() {
    let defaults = freshDefaults()
    defaults.set("enormous", forKey: CoverSize.defaultsKey)
    #expect(CoverSize.saved(in: defaults) == .medium)
}
