import AppKit
import KeyboardShortcuts
import Testing
@testable import ClutterCore

@MainActor @Test func settingsWindowHasAShortcutRecorder() {
    let settings = SettingsWindowController()
    #expect(settings.window.title == "Settings")
    #expect(settings.window.styleMask.contains(.closable))
    let recorders = settings.window.contentView?.subviews.compactMap { $0 as? KeyboardShortcuts.RecorderCocoa }
    #expect(recorders?.count == 1)
}

@Test func addCurrentAlbumShortcutName() {
    #expect(KeyboardShortcuts.Name.addCurrentAlbum.rawValue == "addCurrentAlbum")
}
