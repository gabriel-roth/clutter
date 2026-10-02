import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut for adding the album Spotify is playing. No default.
    public static let addCurrentAlbum = Self("addCurrentAlbum")
    /// Global shortcut for showing or hiding the covers. No default.
    public static let toggleClutter = Self("toggleClutter")
}

/// Closes on Command-W itself, since the menu bar has no Close item.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "w" else { return false }
        performClose(nil)
        return true
    }
}

/// A small window for choosing the global shortcuts for showing or hiding the covers and for adding
/// the current album, how many albums to show, whether hovering shows album info, and whether covers are turned.
@MainActor
public final class SettingsWindowController: NSObject {
    /// How long the album count must stay unchanged before it's reported, so stepping from 10 to 15
    /// fetches once. Pressing Return in the field (or leaving it) reports without waiting.
    static let changeDelay: Duration = .milliseconds(500)

    public let window: NSWindow
    let albumCountField = NSTextField()
    let albumCountStepper = NSStepper()
    let showsInfoOnHoverCheckbox = NSButton(checkboxWithTitle: "Show album info", target: nil, action: nil)
    let skewsCoversCheckbox = NSButton(checkboxWithTitle: "Skew covers", target: nil, action: nil)
    private var albumCount: Int
    /// The count `onAlbumCountChange` last got, or the starting count.
    private var reportedAlbumCount: Int
    private let onAlbumCountChange: @MainActor (Int) -> Void
    private let onShowsInfoOnHoverChange: @MainActor (Bool) -> Void
    private let onSkewsCoversChange: @MainActor (Bool) -> Void
    private var pendingChange: Task<Void, Never>?

    /// `onAlbumCountChange` gets the new count once it settles, and `onShowsInfoOnHoverChange` and
    /// `onSkewsCoversChange` their checkbox's new state right away; each is responsible for saving its setting.
    public init(
        albumCount: Int,
        showsInfoOnHover: Bool = true,
        skewsCovers: Bool = true,
        onAlbumCountChange: @escaping @MainActor (Int) -> Void = { _ in },
        onShowsInfoOnHoverChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onSkewsCoversChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.albumCount = albumCount
        self.reportedAlbumCount = albumCount
        self.onAlbumCountChange = onAlbumCountChange
        self.onShowsInfoOnHoverChange = onShowsInfoOnHoverChange
        self.onSkewsCoversChange = onSkewsCoversChange
        window = SettingsWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
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

        let countRow = NSStackView(views: [NSTextField(labelWithString: "Number of albums to show:"), albumCountField, albumCountStepper])
        countRow.orientation = .horizontal
        countRow.spacing = 8

        showsInfoOnHoverCheckbox.state = showsInfoOnHover ? .on : .off
        showsInfoOnHoverCheckbox.imagePosition = .imageTrailing
        showsInfoOnHoverCheckbox.target = self
        showsInfoOnHoverCheckbox.action = #selector(showsInfoOnHoverChanged(_:))

        skewsCoversCheckbox.state = skewsCovers ? .on : .off
        skewsCoversCheckbox.imagePosition = .imageTrailing
        skewsCoversCheckbox.target = self
        skewsCoversCheckbox.action = #selector(skewsCoversChanged(_:))

        func shortcutRow(_ title: String, _ name: KeyboardShortcuts.Name) -> NSStackView {
            let row = NSStackView(views: [NSTextField(labelWithString: title), KeyboardShortcuts.RecorderCocoa(for: name)])
            row.orientation = .horizontal
            row.spacing = 8
            return row
        }

        let rows = NSStackView(views: [
            shortcutRow("Show/hide Clutter", .toggleClutter),
            shortcutRow("Add currently playing album", .addCurrentAlbum),
            countRow,
            showsInfoOnHoverCheckbox,
            skewsCoversCheckbox,
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        // Leading-aligned rows only weakly respect the right inset, so the window would size itself
        // with the widest row flush against its edge.
        for row in rows.arrangedSubviews {
            row.trailingAnchor.constraint(lessThanOrEqualTo: rows.trailingAnchor, constant: -rows.edgeInsets.right).isActive = true
        }

        window.title = "Clutter settings"
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
        guard let value = Int(sender.stringValue.trimmingCharacters(in: .whitespaces)) else {
            albumCountField.integerValue = albumCount
            return
        }
        setAlbumCount(value)
        reportAlbumCount()
    }

    @objc func showsInfoOnHoverChanged(_ sender: NSButton) {
        onShowsInfoOnHoverChange(sender.state == .on)
    }

    @objc func skewsCoversChanged(_ sender: NSButton) {
        onSkewsCoversChange(sender.state == .on)
    }

    private func setAlbumCount(_ count: Int) {
        let count = AlbumCount.clamped(count)
        if albumCountField.integerValue != count { albumCountField.integerValue = count }
        albumCountStepper.integerValue = count
        guard count != albumCount else { return }
        albumCount = count
        pendingChange?.cancel()
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: Self.changeDelay)
            guard !Task.isCancelled, let self else { return }
            self.reportAlbumCount()
        }
    }

    /// Reports the count now, if it hasn't been, instead of waiting for a pending report.
    private func reportAlbumCount() {
        pendingChange?.cancel()
        pendingChange = nil
        guard albumCount != reportedAlbumCount else { return }
        reportedAlbumCount = albumCount
        onAlbumCountChange(albumCount)
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) {
        guard let value = Int(albumCountField.stringValue), AlbumCount.range.contains(value) else { return }
        setAlbumCount(value)
    }
}
