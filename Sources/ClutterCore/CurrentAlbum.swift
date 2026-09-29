import Foundation

/// What Spotify is playing, as read through its AppleScript dictionary.
public struct NowPlaying: Equatable, Sendable {
    public let trackURI: String

    public var trackID: String {
        String(trackURI.dropFirst("spotify:track:".count))
    }

    /// Returns the current track's URI, or "" when Spotify isn't running or is stopped. Never launches Spotify.
    public static let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is not stopped then
                    return spotify url of current track
                end if
            end tell
        end if
        return ""
        """

    /// Nil for anything that isn't a Spotify catalog track (podcasts, ads, local files).
    public static func parse(_ output: String) -> NowPlaying? {
        let uri = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard uri.hasPrefix("spotify:track:") else { return nil }
        return NowPlaying(trackURI: uri)
    }
}

/// Spotify's public track page, whose `music:album` meta tag names the track's album.
public enum TrackPage {
    public static func url(forTrackID id: String) -> URL {
        URL(string: "https://open.spotify.com/track/\(id)")!
    }

    public static func albumURI(fromHTML html: String) -> String? {
        let tag = #/<meta name="music:album" content="https://open\.spotify\.com/album/([A-Za-z0-9]+)"/#
        guard let match = html.firstMatch(of: tag) else { return nil }
        return "spotify:album:\(match.1)"
    }
}

public enum CurrentAlbumError: Error, Equatable {
    case nothingPlaying
    case albumNotFound
}

/// Works out which album Spotify is playing.
public struct CurrentAlbumFetcher: Sendable {
    private let nowPlaying: @Sendable () async -> String
    private let http: @Sendable (URL) async throws -> Data

    public init(
        nowPlaying: @escaping @Sendable () async -> String,
        http: @escaping @Sendable (URL) async throws -> Data
    ) {
        self.nowPlaying = nowPlaying
        self.http = http
    }

    public func fetchAlbumURI() async throws -> String {
        guard let playing = NowPlaying.parse(await nowPlaying()) else {
            throw CurrentAlbumError.nothingPlaying
        }
        let page = try await http(TrackPage.url(forTrackID: playing.trackID))
        guard let albumURI = TrackPage.albumURI(fromHTML: String(decoding: page, as: UTF8.self)) else {
            throw CurrentAlbumError.albumNotFound
        }
        return albumURI
    }
}

extension CurrentAlbumFetcher {
    /// Reads Spotify through AppleScript and fetches over HTTPS.
    public static let live = CurrentAlbumFetcher(
        nowPlaying: { await AppleScriptRunner.run(NowPlaying.script) },
        http: { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            return data
        }
    )
}
