import Foundation
import Security

public protocol SpotifyTokenStore: Sendable {
    func load() -> SpotifyTokens?
    func save(_ tokens: SpotifyTokens) throws
    func delete()
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Keeps the tokens as one JSON generic-password item in the login keychain.
public struct KeychainTokenStore: SpotifyTokenStore {
    public let service: String
    public let account: String

    public init(service: String = "com.gabrielroth.Clutter.spotify", account: String = "tokens") {
        self.service = service
        self.account = account
    }

    /// Nil when there's no item, or it holds something that isn't tokens.
    public func load() -> SpotifyTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    public func save(_ tokens: SpotifyTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
