import Foundation

/// How many of the most recently saved albums to show, chosen in Settings and remembered between launches.
public enum AlbumCount {
    public static let range = 1...100
    public static let defaultValue = 10
    static let defaultsKey = "albumCount"

    /// The saved count, clamped into `range`, or `defaultValue` if none is saved.
    public static func saved(in defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultValue }
        return clamped(defaults.integer(forKey: defaultsKey))
    }

    public static func save(_ count: Int, in defaults: UserDefaults) {
        defaults.set(clamped(count), forKey: defaultsKey)
    }

    public static func clamped(_ count: Int) -> Int {
        min(max(count, range.lowerBound), range.upperBound)
    }
}
