import Foundation

public enum SpotifyAuthError: Error, Equatable, LocalizedError {
    case denied(String)
    case stateMismatch
    case missingCode
    case tokenRequestFailed(status: Int, body: String)
    case malformedTokenResponse
    case notSignedIn
    case authorizationExpired

    public var errorDescription: String? {
        switch self {
        case .denied(let reason): "Spotify didn't allow access (\(reason))."
        case .stateMismatch: "Spotify's reply didn't match this sign-in attempt."
        case .missingCode: "Spotify's reply didn't include an authorization code."
        case .tokenRequestFailed(let status, _): "Spotify's sign-in service returned an error (HTTP \(status))."
        case .malformedTokenResponse: "Spotify's sign-in service sent a reply Clutter couldn't read."
        case .notSignedIn: "Clutter isn't signed in to Spotify."
        case .authorizationExpired: "Clutter's Spotify sign-in has expired. Sign in again."
        }
    }
}
