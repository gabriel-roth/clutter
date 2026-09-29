import Foundation
import Testing
@testable import ClutterCore

private let config = SpotifyAuthConfig(clientID: "CLIENT", redirectURI: "clutter://callback", scopes: ["user-library-read"])
private let t0 = Date(timeIntervalSince1970: 1_000_000)
private let tokenJSON = #"{"access_token":"AT","token_type":"Bearer","scope":"user-library-read","expires_in":3600,"refresh_token":"RT"}"#

private func makeAuth(store: MemoryTokenStore = MemoryTokenStore(), http: FakeHTTP) -> SpotifyAuth {
    SpotifyAuth(config: config, store: store, http: { try http.handle($0) }, now: { t0 })
}

private func queryItems(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

private func formFields(_ request: URLRequest) -> [String: String] {
    var components = URLComponents()
    components.percentEncodedQuery = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

/// Plays Spotify's part of the sign-in: approves and redirects back with a code and the same state.
private let approve: @Sendable (URL) async throws -> URL = { url in
    URL(string: "clutter://callback?code=CODE&state=\(queryItems(url)["state"]!)")!
}

@Test func clutterSignsInAsItsOwnSpotifyApp() {
    #expect(SpotifyAuthConfig.clutter.clientID == "45ae3a8fba3f4d4f801fbeaf67a64b03")
    #expect(SpotifyAuthConfig.clutter.redirectURI == "clutter://callback")
    #expect(SpotifyAuthConfig.clutter.scopes == ["user-library-read"])
    #expect(SpotifyAuthConfig.clutter.callbackScheme == "clutter")
}

@Test func authorizationURLAsksForTheLibraryWithPKCE() {
    let auth = makeAuth(http: FakeHTTP([]))
    let url = auth.authorizationURL(pkce: PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), state: "STATE")
    #expect(url.scheme == "https")
    #expect(url.host == "accounts.spotify.com")
    #expect(url.path == "/authorize")
    #expect(queryItems(url) == [
        "response_type": "code",
        "client_id": "CLIENT",
        "redirect_uri": "clutter://callback",
        "scope": "user-library-read",
        "state": "STATE",
        "code_challenge_method": "S256",
        "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
    ])
}

@Test func callbackCodeIsExtracted() throws {
    #expect(try SpotifyAuth.code(fromCallback: URL(string: "clutter://callback?code=ABC&state=S")!, expectedState: "S") == "ABC")
}

@Test func deniedCallbackThrows() {
    #expect(throws: SpotifyAuthError.denied("access_denied")) {
        try SpotifyAuth.code(fromCallback: URL(string: "clutter://callback?error=access_denied&state=S")!, expectedState: "S")
    }
}

@Test func callbackFromAnotherAttemptThrows() {
    #expect(throws: SpotifyAuthError.stateMismatch) {
        try SpotifyAuth.code(fromCallback: URL(string: "clutter://callback?code=ABC&state=OTHER")!, expectedState: "S")
    }
}

@Test func callbackWithoutACodeThrows() {
    #expect(throws: SpotifyAuthError.missingCode) {
        try SpotifyAuth.code(fromCallback: URL(string: "clutter://callback?state=S")!, expectedState: "S")
    }
}

@Test func signInExchangesTheCodeAndSavesTheTokens() async throws {
    let store = MemoryTokenStore()
    let http = FakeHTTP([(200, tokenJSON)])
    let auth = makeAuth(store: store, http: http)
    let authorizeURL = Box<URL?>(nil)
    try await auth.signIn { url in
        authorizeURL.value = url
        return try await approve(url)
    }
    let request = try #require(http.recorded.first)
    #expect(http.recorded.count == 1)
    #expect(request.url?.absoluteString == "https://accounts.spotify.com/api/token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let form = formFields(request)
    #expect(form["grant_type"] == "authorization_code")
    #expect(form["code"] == "CODE")
    #expect(form["redirect_uri"] == "clutter://callback")
    #expect(form["client_id"] == "CLIENT")
    let challenge = try #require(authorizeURL.value.map { queryItems($0)["code_challenge"] })
    #expect(PKCE(verifier: form["code_verifier"] ?? "").challenge == challenge)
    #expect(store.load() == SpotifyTokens(accessToken: "AT", refreshToken: "RT", expiresAt: t0 + 3600))
    #expect(await auth.isSignedIn)
}

@Test func failedCodeExchangeSavesNothing() async {
    let store = MemoryTokenStore()
    let auth = makeAuth(store: store, http: FakeHTTP([(400, #"{"error":"invalid_grant"}"#)]))
    await #expect(throws: SpotifyAuthError.tokenRequestFailed(status: 400, body: #"{"error":"invalid_grant"}"#)) {
        try await auth.signIn(authorize: approve)
    }
    #expect(store.load() == nil)
}

@Test func malformedTokenReplyThrows() async {
    let store = MemoryTokenStore()
    let auth = makeAuth(store: store, http: FakeHTTP([(200, "not json")]))
    await #expect(throws: SpotifyAuthError.malformedTokenResponse) {
        try await auth.signIn(authorize: approve)
    }
    #expect(store.load() == nil)
}

@Test func freshTokenIsReturnedWithoutCallingSpotify() async throws {
    let http = FakeHTTP([])
    let store = MemoryTokenStore(SpotifyTokens(accessToken: "AT", refreshToken: "RT", expiresAt: t0 + 600))
    #expect(try await makeAuth(store: store, http: http).validAccessToken() == "AT")
    #expect(http.recorded.isEmpty)
}

@Test func staleTokenIsRefreshedAndSaved() async throws {
    let store = MemoryTokenStore(SpotifyTokens(accessToken: "OLD", refreshToken: "RT", expiresAt: t0 + 30))
    let http = FakeHTTP([(200, #"{"access_token":"NEW","token_type":"Bearer","expires_in":3600}"#)])
    #expect(try await makeAuth(store: store, http: http).validAccessToken() == "NEW")
    #expect(formFields(http.recorded[0]) == ["grant_type": "refresh_token", "refresh_token": "RT", "client_id": "CLIENT"])
    #expect(store.load() == SpotifyTokens(accessToken: "NEW", refreshToken: "RT", expiresAt: t0 + 3600))
}

@Test func refreshKeepsANewRefreshTokenWhenSpotifySendsOne() async throws {
    let store = MemoryTokenStore(SpotifyTokens(accessToken: "OLD", refreshToken: "RT", expiresAt: t0))
    let http = FakeHTTP([(200, #"{"access_token":"NEW","expires_in":3600,"refresh_token":"RT2"}"#)])
    _ = try await makeAuth(store: store, http: http).validAccessToken()
    #expect(store.load()?.refreshToken == "RT2")
}

@Test func expiredAuthorizationForgetsTheTokens() async {
    let store = MemoryTokenStore(SpotifyTokens(accessToken: "OLD", refreshToken: "RT", expiresAt: t0))
    let auth = makeAuth(store: store, http: FakeHTTP([(400, #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#)]))
    await #expect(throws: SpotifyAuthError.authorizationExpired) {
        try await auth.validAccessToken()
    }
    #expect(store.load() == nil)
    #expect(await auth.isSignedIn == false)
}

@Test func otherRefreshFailuresKeepTheTokens() async {
    let saved = SpotifyTokens(accessToken: "OLD", refreshToken: "RT", expiresAt: t0)
    let store = MemoryTokenStore(saved)
    let auth = makeAuth(store: store, http: FakeHTTP([(503, "unavailable")]))
    await #expect(throws: SpotifyAuthError.tokenRequestFailed(status: 503, body: "unavailable")) {
        try await auth.validAccessToken()
    }
    #expect(store.load() == saved)
}

@Test func noTokensMeansNotSignedIn() async {
    let auth = makeAuth(http: FakeHTTP([]))
    #expect(await auth.isSignedIn == false)
    await #expect(throws: SpotifyAuthError.notSignedIn) {
        try await auth.validAccessToken()
    }
}
