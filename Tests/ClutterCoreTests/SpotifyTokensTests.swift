import Foundation
import Testing
@testable import ClutterCore

@Test func tokensAreFreshUntilTheLastMinute() {
    let tokens = SpotifyTokens(accessToken: "AT", refreshToken: "RT", expiresAt: Date(timeIntervalSince1970: 1000))
    #expect(tokens.isFresh(at: Date(timeIntervalSince1970: 939)))
    #expect(!tokens.isFresh(at: Date(timeIntervalSince1970: 940)))
}

@Test func tokenResponseBecomesTokens() throws {
    let json = #"{"access_token":"AT","token_type":"Bearer","scope":"user-library-read","expires_in":3600,"refresh_token":"RT"}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    #expect(try response.tokens(receivedAt: Date(timeIntervalSince1970: 100), previousRefreshToken: nil, previousScopes: nil)
        == SpotifyTokens(accessToken: "AT", refreshToken: "RT", expiresAt: Date(timeIntervalSince1970: 3700), scopes: ["user-library-read"]))
}

@Test func responseWithoutARefreshTokenKeepsThePreviousOne() throws {
    let json = #"{"access_token":"NEW","token_type":"Bearer","expires_in":3600}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    #expect(try response.tokens(receivedAt: Date(timeIntervalSince1970: 0), previousRefreshToken: "OLD", previousScopes: nil).refreshToken == "OLD")
}

@Test func responseWithNoRefreshTokenAtAllIsMalformed() throws {
    let json = #"{"access_token":"AT","token_type":"Bearer","expires_in":3600}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    #expect(throws: SpotifyAuthError.malformedTokenResponse) {
        try response.tokens(receivedAt: Date(timeIntervalSince1970: 0), previousRefreshToken: nil, previousScopes: nil)
    }
}

@Test func tokenResponseRecordsTheGrantedScopes() throws {
    let json = #"{"access_token":"AT","token_type":"Bearer","scope":"user-library-read user-library-modify","expires_in":3600,"refresh_token":"RT"}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    let tokens = try response.tokens(receivedAt: Date(timeIntervalSince1970: 0), previousRefreshToken: nil, previousScopes: nil)
    #expect(tokens.scopes == ["user-library-read", "user-library-modify"])
}

@Test func responseWithoutAScopeKeepsThePreviousScopes() throws {
    let json = #"{"access_token":"NEW","token_type":"Bearer","expires_in":3600}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    let tokens = try response.tokens(receivedAt: Date(timeIntervalSince1970: 0), previousRefreshToken: "OLD", previousScopes: ["user-library-read"])
    #expect(tokens.scopes == ["user-library-read"])
}

@Test func tokensSavedBeforeScopesWereRecordedDecodeWithNoScopes() throws {
    let json = #"{"accessToken":"AT","refreshToken":"RT","expiresAt":0}"#
    let tokens = try JSONDecoder().decode(SpotifyTokens.self, from: Data(json.utf8))
    #expect(tokens.scopes == nil)
    #expect(tokens.accessToken == "AT")
}

@Test func errorsHaveReadableDescriptions() {
    #expect(SpotifyAuthError.denied("access_denied").localizedDescription == "Spotify didn't allow access (access_denied).")
    #expect(SpotifyAuthError.authorizationExpired.localizedDescription == "Clutter's Spotify sign-in has expired. Sign in again.")
}
