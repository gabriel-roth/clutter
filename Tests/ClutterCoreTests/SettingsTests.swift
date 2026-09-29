import AppKit
import KeyboardShortcuts
import Testing
@testable import ClutterCore

private func allSubviews(of view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
}

@MainActor @Test func settingsWindowHasAShortcutRecorder() {
    let settings = SettingsWindowController(albumCount: 10, onAlbumCountChange: { _ in })
    #expect(settings.window.title == "Settings")
    #expect(settings.window.styleMask.contains(.closable))
    #expect(allSubviews(of: settings.window.contentView).compactMap { $0 as? KeyboardShortcuts.RecorderCocoa }.count == 1)
}

@MainActor @Test func albumCountControlsShowTheCurrentCountWithinRange() {
    let settings = SettingsWindowController(albumCount: 25, onAlbumCountChange: { _ in })
    #expect(settings.albumCountField.integerValue == 25)
    #expect(settings.albumCountStepper.integerValue == 25)
    #expect(settings.albumCountStepper.minValue == 1)
    #expect(settings.albumCountStepper.maxValue == 100)
    let formatter = settings.albumCountField.formatter as? NumberFormatter
    #expect(formatter?.minimum == 1)
    #expect(formatter?.maximum == 100)
    #expect(allSubviews(of: settings.window.contentView).contains { $0 === settings.albumCountField })
}

@MainActor @Test func steppingUpdatesTheFieldAndReportsOnceAfterAPause() async throws {
    var reported: [Int] = []
    let settings = SettingsWindowController(albumCount: 10, onAlbumCountChange: { reported.append($0) })
    settings.albumCountStepper.integerValue = 11
    settings.stepperChanged(settings.albumCountStepper)
    settings.albumCountStepper.integerValue = 12
    settings.stepperChanged(settings.albumCountStepper)
    #expect(settings.albumCountField.integerValue == 12)
    #expect(reported.isEmpty)
    try await Task.sleep(for: SettingsWindowController.changeDelay + .milliseconds(300))
    #expect(reported == [12])
}

@MainActor @Test func editingTheFieldUpdatesTheStepperAndClamps() async throws {
    var reported: [Int] = []
    let settings = SettingsWindowController(albumCount: 10, onAlbumCountChange: { reported.append($0) })
    settings.albumCountField.integerValue = 500
    settings.fieldChanged(settings.albumCountField)
    #expect(settings.albumCountStepper.integerValue == 100)
    #expect(settings.albumCountField.integerValue == 100)
    try await Task.sleep(for: SettingsWindowController.changeDelay + .milliseconds(300))
    #expect(reported == [100])
}

@MainActor @Test func settingTheSameCountDoesNotReport() async throws {
    var reported: [Int] = []
    let settings = SettingsWindowController(albumCount: 10, onAlbumCountChange: { reported.append($0) })
    settings.fieldChanged(settings.albumCountField)
    try await Task.sleep(for: SettingsWindowController.changeDelay + .milliseconds(300))
    #expect(reported.isEmpty)
}

@Test func addCurrentAlbumShortcutName() {
    #expect(KeyboardShortcuts.Name.addCurrentAlbum.rawValue == "addCurrentAlbum")
}
