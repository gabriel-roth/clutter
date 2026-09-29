import CoreGraphics
import Foundation

/// How big every cover is, chosen from the View menu and remembered between launches.
public enum CoverSize: String, CaseIterable, Sendable {
    case small, medium, large

    static let defaultsKey = "coverSize"

    public var points: CGFloat {
        switch self {
        case .small: 160
        case .medium: 220
        case .large: 300
        }
    }

    public var title: String {
        rawValue.capitalized
    }

    /// The saved size, or medium if none (or an unrecognized one) is saved.
    public static func saved(in defaults: UserDefaults) -> CoverSize {
        defaults.string(forKey: defaultsKey).flatMap(CoverSize.init(rawValue:)) ?? .medium
    }

    public func save(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
