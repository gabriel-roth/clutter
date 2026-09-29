import Foundation

/// Which Spotify app Clutter signs in as, where Spotify sends the user back, and what access it asks for.
public struct SpotifyAuthConfig: Sendable {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    public init(clientID: String, redirectURI: String, scopes: [String]) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    public static let clutter = SpotifyAuthConfig(
        clientID: "45ae3a8fba3f4d4f801fbeaf67a64b03",
        redirectURI: "clutter://callback",
        scopes: ["user-library-read"]
    )

    /// The scheme of `redirectURI`, which the web sign-in session watches for.
    public var callbackScheme: String {
        URL(string: redirectURI)?.scheme ?? ""
    }
}

/// Signs in to Spotify with the Authorization Code flow and PKCE, and keeps the access token valid.
public actor SpotifyAuth {
    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!

    private let config: SpotifyAuthConfig
    private let store: SpotifyTokenStore
    private let http: HTTP
    private let now: @Sendable () -> Date
    private var refreshTask: Task<SpotifyTokens, Error>?

    public init(
        config: SpotifyAuthConfig = .clutter,
        store: SpotifyTokenStore = KeychainTokenStore(),
        http: @escaping HTTP = { try await URLSession.shared.data(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.store = store
        self.http = http
        self.now = now
    }

    public var isSignedIn: Bool {
        store.load() != nil
    }

    public nonisolated func authorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
        ]
        return components.url!
    }

    /// The authorization code from Spotify's redirect back to Clutter.
    public static func code(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        if let error = value("error") {
            throw SpotifyAuthError.denied(error)
        }
        guard value("state") == expectedState else {
            throw SpotifyAuthError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw SpotifyAuthError.missingCode
        }
        return code
    }

    /// `authorize` shows Spotify's sign-in page at the URL it's given and returns the URL Spotify
    /// redirects back to.
    public func signIn(authorize: @Sendable (URL) async throws -> URL) async throws {
        let pkce = PKCE()
        let state = PKCE.randomString()
        let callback = try await authorize(authorizationURL(pkce: pkce, state: state))
        let code = try Self.code(fromCallback: callback, expectedState: state)
        let tokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": pkce.verifier,
        ], previousRefreshToken: nil)
        try store.save(tokens)
    }

    /// A usable access token, refreshed first if it's about to expire.
    public func validAccessToken() async throws -> String {
        guard let tokens = store.load() else {
            throw SpotifyAuthError.notSignedIn
        }
        if tokens.isFresh(at: now()) {
            return tokens.accessToken
        }
        // Callers that find the token stale while a refresh is running share that refresh.
        let task: Task<SpotifyTokens, Error>
        if let running = refreshTask {
            task = running
        } else {
            task = Task { try await self.refresh(tokens) }
            refreshTask = task
        }
        return try await task.value.accessToken
    }

    private func refresh(_ tokens: SpotifyTokens) async throws -> SpotifyTokens {
        defer { refreshTask = nil }
        do {
            let refreshed = try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": tokens.refreshToken,
                "client_id": config.clientID,
            ], previousRefreshToken: tokens.refreshToken)
            try store.save(refreshed)
            return refreshed
        } catch SpotifyAuthError.tokenRequestFailed(let status, let body) where status == 400 && body.contains(#""invalid_grant""#) {
            // Spotify ends an authorization after six months, or when the user revokes it.
            // Forget the tokens only if a sign-in hasn't replaced them in the meantime.
            if store.load()?.refreshToken == tokens.refreshToken {
                store.delete()
            }
            throw SpotifyAuthError.authorizationExpired
        }
    }

    private func requestTokens(_ form: [String: String], previousRefreshToken: String?) async throws -> SpotifyTokens {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)
        let (data, response) = try await http(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(decoding: data, as: UTF8.self)
            throw SpotifyAuthError.tokenRequestFailed(status: status, body: body)
        }
        guard let reply = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw SpotifyAuthError.malformedTokenResponse
        }
        return try reply.tokens(receivedAt: now(), previousRefreshToken: previousRefreshToken)
    }

    static func formBody(_ form: [String: String]) -> Data {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = form.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
