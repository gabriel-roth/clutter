import Foundation

/// Whether covers are shown turned, chosen in Settings and remembered between launches. Each cover's
/// turn is saved either way, so turning this back on restores it.
public enum SkewCovers {
    static let defaultsKey = "skewsCovers"

    /// The saved setting, or on if none is saved.
    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    public static func save(_ isEnabled: Bool, in defaults: UserDefaults) {
        defaults.set(isEnabled, forKey: defaultsKey)
    }
}
