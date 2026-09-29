import CoreGraphics

enum WindowStack {
    /// Whether the frontmost ordinary (layer 0) window on screen belongs to `pid`. Reading owner
    /// process IDs needs no screen-recording permission.
    static func topWindowBelongs(toProcess pid: Int32) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let top = info.first { ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
        return top?[kCGWindowOwnerPID as String] as? Int32 == pid
    }
}
