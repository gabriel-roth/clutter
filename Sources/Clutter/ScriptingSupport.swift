import AppKit

extension NSApplication {
    /// Backs the `has key window` property in Clutter.sdef. The covers are borderless windows in an
    /// accessory app, so clicking one can make it key without Clutter owning the menu bar; that's
    /// the state in which Command-comma reaches Clutter's menu, and what `frontmost` can't report.
    @objc var clutterHasKeyWindow: Bool { keyWindow != nil }
}
