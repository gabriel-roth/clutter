import AppKit
@testable import ClutterCore

/// A fresh, empty directory path that doesn't exist yet.
func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "ClutterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A small valid JPEG.
func jpegData() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 3,
        hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .jpeg, properties: [:])!
}

/// Deterministic generator (SplitMix64) so random placement is repeatable in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class SpyPlayer: SpotifyPlayer {
    var played: [Album] = []
    func play(_ album: Album) { played.append(album) }
}

/// A thread-safe box for values captured by `@Sendable` test closures.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Answers HTTP requests with canned (status, body) replies in order and records every request.
/// Throws once the replies run out, so an unexpected call fails the test.
final class FakeHTTP: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(status: Int, body: String, headers: [String: String])]
    private var requests: [URLRequest] = []

    init(_ replies: [(status: Int, body: String)]) {
        self.replies = replies.map { ($0.status, $0.body, [:]) }
    }

    /// Replies that also carry response headers.
    init(withHeaders replies: [(status: Int, body: String, headers: [String: String])]) {
        self.replies = replies
    }

    var recorded: [URLRequest] {
        lock.withLock { requests }
    }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        try lock.withLock {
            requests.append(request)
            guard !replies.isEmpty else { throw URLError(.resourceUnavailable) }
            let reply = replies.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
            return (Data(reply.body.utf8), response)
        }
    }
}

/// Keeps tokens in memory instead of the Keychain.
final class MemoryTokenStore: SpotifyTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SpotifyTokens?

    init(_ tokens: SpotifyTokens? = nil) {
        self.tokens = tokens
    }

    func load() -> SpotifyTokens? { lock.withLock { tokens } }
    func save(_ tokens: SpotifyTokens) throws { lock.withLock { self.tokens = tokens } }
    func delete() { lock.withLock { tokens = nil } }
}
