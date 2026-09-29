import Foundation

/// Whether hovering over a cover shows its artist and title, chosen in Settings and remembered between launches.
public enum HoverInfo {
    static let defaultsKey = "showsInfoOnHover"

    /// The saved setting, or on if none is saved.
    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }

    public static func save(_ isEnabled: Bool, in defaults: UserDefaults) {
        defaults.set(isEnabled, forKey: defaultsKey)
    }
}
