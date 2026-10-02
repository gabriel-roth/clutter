import Foundation
import Testing
@testable import ClutterCore

@Test func skewCoversIsOnByDefault() {
    #expect(SkewCovers.isEnabled(in: freshDefaults()))
}

@Test func savedSkewCoversSettingLoadsBack() {
    let defaults = freshDefaults()
    SkewCovers.save(false, in: defaults)
    #expect(!SkewCovers.isEnabled(in: defaults))
    SkewCovers.save(true, in: defaults)
    #expect(SkewCovers.isEnabled(in: defaults))
}
