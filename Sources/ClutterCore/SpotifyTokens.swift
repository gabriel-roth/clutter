import Foundation

/// What Spotify's token endpoint grants: a short-lived access token and the refresh token that renews it.
public struct SpotifyTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
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

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    /// Spotify may leave out the refresh token when refreshing; then the previous one stays valid.
    func tokens(receivedAt now: Date, previousRefreshToken: String?) throws -> SpotifyTokens {
        guard let refreshToken = refreshToken ?? previousRefreshToken else {
            throw SpotifyAuthError.malformedTokenResponse
        }
        return SpotifyTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(expiresIn))
    }
}
