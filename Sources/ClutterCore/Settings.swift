import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut for adding the album Spotify is playing. No default.
    public static let addCurrentAlbum = Self("addCurrentAlbum")
}

/// A small window for choosing how many albums to show and the global "add current album" shortcut.
@MainActor
public final class SettingsWindowController: NSObject {
    /// How long the album count must stay unchanged before it's reported, so stepping from 10 to 15
    /// fetches once.
    static let changeDelay: Duration = .milliseconds(500)

    public let window: NSWindow
    let albumCountField = NSTextField()
    let albumCountStepper = NSStepper()
    private var albumCount: Int
    private let onAlbumCountChange: @MainActor (Int) -> Void
    private var pendingChange: Task<Void, Never>?

    /// `onAlbumCountChange` gets the new count once it settles; it's responsible for saving it.
    public init(albumCount: Int, onAlbumCountChange: @escaping @MainActor (Int) -> Void) {
        self.albumCount = albumCount
        self.onAlbumCountChange = onAlbumCountChange
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        super.init()

        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: AlbumCount.range.lowerBound)
        formatter.maximum = NSNumber(value: AlbumCount.range.upperBound)
        albumCountField.formatter = formatter
        albumCountField.integerValue = albumCount
        albumCountField.alignment = .right
        albumCountField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        albumCountField.delegate = self
        albumCountField.target = self
        albumCountField.action = #selector(fieldChanged(_:))

        albumCountStepper.minValue = Double(AlbumCount.range.lowerBound)
        albumCountStepper.maxValue = Double(AlbumCount.range.upperBound)
        albumCountStepper.increment = 1
        albumCountStepper.valueWraps = false
        albumCountStepper.integerValue = albumCount
        albumCountStepper.target = self
        albumCountStepper.action = #selector(stepperChanged(_:))

        let countRow = NSStackView(views: [NSTextField(labelWithString: "Albums on desktop:"), albumCountField, albumCountStepper])
        countRow.orientation = .horizontal
        countRow.spacing = 8

        let shortcutRow = NSStackView(views: [
            NSTextField(labelWithString: "Add currently playing album:"),
            KeyboardShortcuts.RecorderCocoa(for: .addCurrentAlbum),
        ])
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 8

        let rows = NSStackView(views: [countRow, shortcutRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = rows
        window.setContentSize(rows.fittingSize)
        window.center()
    }

    public func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc func stepperChanged(_ sender: NSStepper) {
        setAlbumCount(sender.integerValue)
    }

    @objc func fieldChanged(_ sender: NSTextField) {
        setAlbumCount(sender.integerValue)
    }

    private func setAlbumCount(_ count: Int) {
        let count = AlbumCount.clamped(count)
        albumCountField.integerValue = count
        albumCountStepper.integerValue = count
        guard count != albumCount else { return }
        albumCount = count
        pendingChange?.cancel()
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: Self.changeDelay)
            guard !Task.isCancelled, let self else { return }
            self.onAlbumCountChange(count)
        }
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) {
        guard let value = Int(albumCountField.stringValue), AlbumCount.range.contains(value) else { return }
        albumCountStepper.integerValue = value
        guard value != albumCount else { return }
        setAlbumCount(value)
    }
}
