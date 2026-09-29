import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut for adding the album Spotify is playing. No default.
    public static let addCurrentAlbum = Self("addCurrentAlbum")
}

/// A small window for choosing the global "add current album" shortcut.
@MainActor
public final class SettingsWindowController {
    public let window: NSWindow

    public init() {
        let row = NSStackView(views: [
            NSTextField(labelWithString: "Add currently playing album:"),
            KeyboardShortcuts.RecorderCocoa(for: .addCurrentAlbum),
        ])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = row
        window.setContentSize(row.fittingSize)
        window.center()
    }

    public func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
