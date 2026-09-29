import Foundation

/// An album in the user's Spotify library and when it was saved.
public struct SavedAlbum: Equatable, Sendable {
    public let album: Album
    public let addedAt: Date
    /// The largest cover image Spotify lists, if any.
    public let artworkURL: URL?

    public init(album: Album, addedAt: Date, artworkURL: URL?) {
        self.album = album
        self.addedAt = addedAt
        self.artworkURL = artworkURL
    }
}

public enum SpotifyLibraryError: Error, Equatable {
    /// `retryAfter` is the Retry-After header's seconds, when the reply has a readable one.
    case requestFailed(status: Int, body: String, retryAfter: Int? = nil)
    case malformedResponse
    /// The album was removed to move it to the top, but saving it again kept failing.
    case removedButNotSaved(albumURI: String)
}

/// Reads and edits the albums saved in the user's Spotify library through the Web API.
public struct SpotifyLibrary: Sendable {
    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let apiBase = URL(string: "https://api.spotify.com/v1")!
    static let pageSize = 50

    private let accessToken: @Sendable () async throws -> String
    private let http: HTTP
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        accessToken: @escaping @Sendable () async throws -> String,
        http: @escaping HTTP = { try await URLSession.shared.data(for: $0) },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.accessToken = accessToken
        self.http = http
        self.sleep = sleep
    }

    /// Up to `count` of the most recently saved albums, newest first.
    public func recentAlbums(count: Int) async throws -> [SavedAlbum] {
        var albums: [SavedAlbum] = []
        while albums.count < count {
            let limit = min(Self.pageSize, count - albums.count)
            let data = try await send("GET", "me/albums", query: [("limit", "\(limit)"), ("offset", "\(albums.count)")])
            guard let page = try? Self.makeDecoder().decode(SavedAlbumsPage.self, from: data) else {
                throw SpotifyLibraryError.malformedResponse
            }
            albums += page.items.map(\.savedAlbum)
            if page.next == nil || page.items.count < limit { break }
        }
        // Spotify doesn't document the order, so don't rely on it.
        return albums.sorted { $0.addedAt > $1.addedAt }
    }

    public func contains(albumURI: String) async throws -> Bool {
        let data = try await send("GET", "me/library/contains", query: [("uris", albumURI)])
        guard let saved = try? JSONDecoder().decode([Bool].self, from: data).first else {
            throw SpotifyLibraryError.malformedResponse
        }
        return saved
    }

    public func save(albumURI: String) async throws {
        _ = try await send("PUT", "me/library", query: [("uris", albumURI)])
    }

    public func remove(albumURI: String) async throws {
        _ = try await send("DELETE", "me/library", query: [("uris", albumURI)])
    }

    /// Saves the album, first removing it if it's already saved so it becomes the most recently added.
    /// After a remove, a failed save is tried twice more, since giving up would leave the album
    /// out of the library; if every try fails this throws `.removedButNotSaved`.
    public func bumpToMostRecent(albumURI: String) async throws {
        guard try await contains(albumURI: albumURI) else {
            return try await save(albumURI: albumURI)
        }
        try await remove(albumURI: albumURI)
        let backoff: [Duration] = [.seconds(1), .seconds(2)]
        for attempt in 0...backoff.count {
            do {
                return try await save(albumURI: albumURI)
            } catch {
                NSLog("Clutter: couldn't re-save %@ (try %d): %@", albumURI, attempt + 1, String(describing: error))
                guard attempt < backoff.count else { break }
                // A cancelled wait still leaves the album removed, so it ends up reported the same way.
                do { try await sleep(Self.retryDelay(after: error, default: backoff[attempt])) } catch { break }
            }
        }
        throw SpotifyLibraryError.removedButNotSaved(albumURI: albumURI)
    }

    /// A rate limit's Retry-After, capped at 10 seconds (1 if missing); otherwise `fallback`.
    private static func retryDelay(after error: any Error, default fallback: Duration) -> Duration {
        guard case SpotifyLibraryError.requestFailed(429, _, let retryAfter) = error else { return fallback }
        return .seconds(min(retryAfter ?? 1, 10))
    }

    private func send(_ method: String, _ path: String, query: [(String, String)]) async throws -> Data {
        var components = URLComponents(url: Self.apiBase.appending(path: path), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query.map { "\($0)=\(Self.percentEncoded($1))" }.joined(separator: "&")
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        if method == "PUT" {
            request.httpBody = Data()  // Sends Content-Length: 0.
        }
        let token = try await accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await http(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .flatMap { $0 >= 0 ? $0 : nil }
            throw SpotifyLibraryError.requestFailed(status: status, body: String(decoding: data, as: UTF8.self), retryAfter: retryAfter)
        }
        return data
    }

    static func percentEncoded(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// `added_at` is ISO 8601, with or without fractional seconds.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: .iso8601) { return date }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(string)"))
        }
        return decoder
    }
}

/// One page of GET /me/albums.
private struct SavedAlbumsPage: Decodable {
    let items: [Item]
    let next: String?

    struct Item: Decodable {
        let addedAt: Date
        let album: AlbumJSON

        enum CodingKeys: String, CodingKey {
            case addedAt = "added_at"
            case album
        }

        var savedAlbum: SavedAlbum {
            SavedAlbum(
                album: Album(
                    title: album.name,
                    artist: album.artists.map(\.name).joined(separator: ", "),
                    spotifyURI: album.uri,
                    artworkName: album.id
                ),
                addedAt: addedAt,
                artworkURL: album.images.max { ($0.width ?? 0) < ($1.width ?? 0) }?.url
            )
        }
    }

    struct AlbumJSON: Decodable {
        let id: String
        let name: String
        let uri: String
        let artists: [Artist]
        let images: [Image]
    }

    struct Artist: Decodable {
        let name: String
    }

    struct Image: Decodable {
        let url: URL
        let width: Int?
    }
}
