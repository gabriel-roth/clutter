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
    #expect(try response.tokens(receivedAt: Date(timeIntervalSince1970: 100), previousRefreshToken: nil)
        == SpotifyTokens(accessToken: "AT", refreshToken: "RT", expiresAt: Date(timeIntervalSince1970: 3700)))
}

@Test func responseWithoutARefreshTokenKeepsThePreviousOne() throws {
    let json = #"{"access_token":"NEW","token_type":"Bearer","expires_in":3600}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    #expect(try response.tokens(receivedAt: Date(timeIntervalSince1970: 0), previousRefreshToken: "OLD").refreshToken == "OLD")
}

@Test func responseWithNoRefreshTokenAtAllIsMalformed() throws {
    let json = #"{"access_token":"AT","token_type":"Bearer","expires_in":3600}"#
    let response = try JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    #expect(throws: SpotifyAuthError.malformedTokenResponse) {
        try response.tokens(receivedAt: Date(timeIntervalSince1970: 0), previousRefreshToken: nil)
    }
}

@Test func errorsHaveReadableDescriptions() {
    #expect(SpotifyAuthError.denied("access_denied").localizedDescription == "Spotify didn't allow access (access_denied).")
    #expect(SpotifyAuthError.authorizationExpired.localizedDescription == "Clutter's Spotify sign-in has expired. Sign in again.")
}
