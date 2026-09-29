import Foundation
import Testing
@testable import ClutterCore

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ClutterTests-\(UUID().uuidString)")!
}

@Test func hoverInfoIsOnByDefault() {
    #expect(HoverInfo.isEnabled(in: freshDefaults()))
}

@Test func savedHoverInfoSettingLoadsBack() {
    let defaults = freshDefaults()
    HoverInfo.save(false, in: defaults)
    #expect(!HoverInfo.isEnabled(in: defaults))
    HoverInfo.save(true, in: defaults)
    #expect(HoverInfo.isEnabled(in: defaults))
}
