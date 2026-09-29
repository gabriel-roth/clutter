import AppKit
import KeyboardShortcuts
import Testing
@testable import ClutterCore

@MainActor
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

@MainActor @Test func typingAValidCountUpdatesTheStepperAndReportsOnce() async throws {
    var reported: [Int] = []
    let settings = SettingsWindowController(albumCount: 10, onAlbumCountChange: { reported.append($0) })
    settings.albumCountField.stringValue = "25"
    settings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: settings.albumCountField))
    #expect(settings.albumCountStepper.integerValue == 25)
    #expect(reported.isEmpty)
    try await Task.sleep(for: SettingsWindowController.changeDelay + .milliseconds(300))
    #expect(reported == [25])
}

@MainActor @Test func typingAnInvalidCountIsIgnored() async throws {
    var reported: [Int] = []
    let settings = SettingsWindowController(albumCount: 10, onAlbumCountChange: { reported.append($0) })
    for text in ["500", "", "abc"] {
        settings.albumCountField.stringValue = text
        settings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: settings.albumCountField))
        #expect(settings.albumCountStepper.integerValue == 10)
    }
    try await Task.sleep(for: SettingsWindowController.changeDelay + .milliseconds(300))
    #expect(reported.isEmpty)
}

@MainActor @Test func committingAnEmptyFieldRevertsToTheCurrentCount() async throws {
    var reported: [Int] = []
    let settings = SettingsWindowController(albumCount: 10, onAlbumCountChange: { reported.append($0) })
    settings.albumCountField.stringValue = ""
    settings.fieldChanged(settings.albumCountField)
    #expect(settings.albumCountField.integerValue == 10)
    #expect(settings.albumCountStepper.integerValue == 10)
    try await Task.sleep(for: SettingsWindowController.changeDelay + .milliseconds(300))
    #expect(reported.isEmpty)
}

@Test func addCurrentAlbumShortcutName() {
    #expect(KeyboardShortcuts.Name.addCurrentAlbum.rawValue == "addCurrentAlbum")
}

@MainActor @Test func hoverInfoCheckboxShowsTheSettingAndReportsChanges() {
    var reported: [Bool] = []
    let settings = SettingsWindowController(albumCount: 10, showsInfoOnHover: true, onShowsInfoOnHoverChange: { reported.append($0) })
    #expect(settings.showsInfoOnHoverCheckbox.state == .on)
    #expect(settings.showsInfoOnHoverCheckbox.title == "Show album info")
    #expect(settings.showsInfoOnHoverCheckbox.imagePosition == .imageTrailing)
    #expect(allSubviews(of: settings.window.contentView).contains { $0 === settings.showsInfoOnHoverCheckbox })
    settings.showsInfoOnHoverCheckbox.state = .off
    settings.showsInfoOnHoverChanged(settings.showsInfoOnHoverCheckbox)
    settings.showsInfoOnHoverCheckbox.state = .on
    settings.showsInfoOnHoverChanged(settings.showsInfoOnHoverCheckbox)
    #expect(reported == [false, true])
}

@MainActor @Test func hoverInfoCheckboxStartsOffWhenTheSettingIsOff() {
    let settings = SettingsWindowController(albumCount: 10, showsInfoOnHover: false)
    #expect(settings.showsInfoOnHoverCheckbox.state == .off)
}

@MainActor @Test func everyRowKeepsAMarginFromTheWindowsRightEdge() throws {
    let settings = SettingsWindowController(albumCount: 10)
    let rows = try #require(settings.window.contentView as? NSStackView)
    rows.layoutSubtreeIfNeeded()
    for row in rows.arrangedSubviews {
        #expect(rows.bounds.maxX - row.frame.maxX >= 20)
    }
}
