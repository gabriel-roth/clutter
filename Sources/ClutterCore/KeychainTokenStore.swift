import Foundation

public protocol SpotifyTokenStore: Sendable {
    func load() -> SpotifyTokens?
    func save(_ tokens: SpotifyTokens) throws
    func delete()
}

/// Keeps the tokens as one JSON generic-password item in the login keychain.
public struct KeychainTokenStore: SpotifyTokenStore {
    private let item: KeychainItem

    public var service: String { item.service }
    public var account: String { item.account }

    public init(service: String = "com.gabrielroth.Clutter.spotify", account: String = "tokens") {
        item = KeychainItem(service: service, account: account)
    }

    /// Nil when there's no item, or it holds something that isn't tokens.
    public func load() -> SpotifyTokens? {
        item.load().flatMap { try? JSONDecoder().decode(SpotifyTokens.self, from: $0) }
    }

    public func save(_ tokens: SpotifyTokens) throws {
        try item.save(JSONEncoder().encode(tokens))
    }

    public func delete() {
        item.delete()
    }
}
