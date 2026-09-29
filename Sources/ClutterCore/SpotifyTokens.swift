import Foundation

/// What Spotify's token endpoint grants: a short-lived access token and the refresh token that renews it.
public struct SpotifyTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    /// What the user granted. Nil for tokens saved before Clutter recorded scopes.
    public var scopes: Set<String>?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scopes: Set<String>? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    /// True while more than a minute of the access token's life remains.
    public func isFresh(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) > 60
    }
}

/// The token endpoint's JSON reply.
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    /// Space-separated. Spotify may leave it out when refreshing.
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }

    /// Spotify may leave out the refresh token and scope when refreshing; then the previous ones stay valid.
    func tokens(receivedAt now: Date, previousRefreshToken: String?, previousScopes: Set<String>?) throws -> SpotifyTokens {
        guard let refreshToken = refreshToken ?? previousRefreshToken else {
            throw SpotifyAuthError.malformedTokenResponse
        }
        let scopes = scope.map { Set($0.split(separator: " ").map(String.init)) } ?? previousScopes
        return SpotifyTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(expiresIn), scopes: scopes)
    }
}
