import Foundation
import Testing
@testable import ClutterCore

@Test func rendersARequest() {
    let data = SwinsianRemoteMessage.render(method: "PUSH", resource: "play_tracks", headers: [("CSeq", "3")], body: Data("[1,2]".utf8))
    #expect(String(decoding: data, as: UTF8.self) == "PUSH play_tracks SWN/1.0\r\nCSeq: 3\r\nContent-Length: 5\r\n\r\n[1,2]")
}

@Test func rendersARequestWithoutABody() {
    let data = SwinsianRemoteMessage.render(method: "NONCE", resource: "/", headers: [("CSeq", "1"), ("Nonce", "N")])
    #expect(String(decoding: data, as: UTF8.self) == "NONCE / SWN/1.0\r\nCSeq: 1\r\nNonce: N\r\n\r\n")
}

@Test func parsesAReplyAndSaysHowMuchItUsed() throws {
    let text = "SWN/1.0 200 OK\r\nNonce: ABC\r\nCSeq: 1\r\n\r\nextra"
    let (reply, used) = try #require(SwinsianRemoteMessage.parse(Data(text.utf8)))
    #expect(reply.status == "SWN/1.0 200 OK")
    #expect(reply.isOK)
    #expect(reply.headers["Nonce"] == "ABC")
    #expect(reply.body.isEmpty)
    #expect(used == text.utf8.count - "extra".utf8.count)
}

@Test func parsesAMessageWithABody() throws {
    let text = "PUSH playback_state SWN/1.0\r\nContent-Length: 4\r\n\r\n{\"a\"}"
    let (reply, used) = try #require(SwinsianRemoteMessage.parse(Data(text.utf8)))
    #expect(reply.status == "PUSH playback_state SWN/1.0")
    #expect(!reply.isOK)
    #expect(String(decoding: reply.body, as: UTF8.self) == "{\"a\"")
    #expect(used == text.utf8.count - 1)
}

@Test func anIncompleteMessageIsNotParsed() {
    #expect(SwinsianRemoteMessage.parse(Data("SWN/1.0 200 OK\r\nCSeq: 1\r\n".utf8)) == nil)
    #expect(SwinsianRemoteMessage.parse(Data("PUSH x SWN/1.0\r\nContent-Length: 9\r\n\r\nabc".utf8)) == nil)
}

@Test func proofIsTheUppercaseHMACOfTheNonceKeyedByTheSecret() {
    // From Python: hmac.new(secret, nonce, hashlib.sha512).hexdigest().upper()
    let secret = String(repeating: "0123456789ABCDEF", count: 8)
    let nonce = String(repeating: "FEDCBA9876543210", count: 4)
    #expect(SwinsianRemote.proof(secret: secret, nonce: nonce) == "5E2DE6F0B221A69EB25FCE098DD151B743836628CE027EFB71A7D88963E3A1DC7E3859392F1CAAD63EB99765431D476B329C60472B9A2ECE166239E571202577")
}

@Test func noncesAre64HexCharacters() {
    let nonce = SwinsianRemote.makeNonce()
    #expect(nonce.count == 64)
    #expect(nonce.allSatisfy { $0.isHexDigit })
    #expect(nonce != SwinsianRemote.makeNonce())
}

/// Answers each request by its method: the secret it accepts decides the HASH reply.
private final class FakeServer: @unchecked Sendable {
    let acceptedSecret: String
    private let lock = NSLock()
    private var log: [(method: String, headers: [String: String], body: String)] = []
    private(set) var connections = 0

    init(acceptedSecret: String) {
        self.acceptedSecret = acceptedSecret
    }

    var requests: [(method: String, headers: [String: String], body: String)] { lock.withLock { log } }

    func connect() -> any SwinsianRemoteConnection {
        lock.withLock { connections += 1 }
        return Connection(server: self)
    }

    struct Connection: SwinsianRemoteConnection {
        let server: FakeServer
        private let nonce = Box("")

        init(server: FakeServer) {
            self.server = server
        }

        func send(_ request: Data) async throws -> SwinsianRemoteMessage.Reply {
            let text = String(decoding: request, as: UTF8.self)
            let (head, body) = text.components(separatedBy: "\r\n\r\n").splitFirst
            let lines = head.components(separatedBy: "\r\n")
            let method = String(lines[0].split(separator: " ")[0])
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let parts = line.components(separatedBy: ": ")
                headers[parts[0]] = parts[1]
            }
            server.lock.withLock { server.log.append((method, headers, body)) }
            switch method {
            case "NONCE":
                nonce.value = headers["Nonce"] ?? ""
                return .init(status: "SWN/1.0 200 OK", headers: [:], body: Data())
            case "HASH":
                let ok = headers["Hash"] == SwinsianRemote.proof(secret: server.acceptedSecret, nonce: nonce.value)
                // Like Swinsian, a wrong proof gets 200 OK too, just without a Hash.
                return .init(status: "SWN/1.0 200 OK", headers: ok ? ["Hash": "H", "Cert": "C"] : [:], body: Data())
            default:
                return .init(status: "PUSH playback_state SWN/1.0", headers: [:], body: Data("{}".utf8))
            }
        }

        func close() {}
    }
}

private extension Array where Element == String {
    var splitFirst: (String, String) { (self[0], dropFirst().joined(separator: "\r\n\r\n")) }
}

private func remote(_ server: FakeServer, cached: String?, inSwinsian: String?) -> (SwinsianRemote, Box<String?>, Box<Int>) {
    let cache = Box(cached), swinsianReads = Box(0)
    let remote = SwinsianRemote(
        connect: { server.connect() },
        secrets: SwinsianRemote.Secrets(
            cached: { cache.value },
            cache: { cache.value = $0 },
            fromSwinsian: {
                swinsianReads.value += 1
                return inSwinsian
            }
        )
    )
    return (remote, cache, swinsianReads)
}

@Test func playsTracksWithTheCachedSecret() async throws {
    let server = FakeServer(acceptedSecret: "S1")
    let (remote, _, swinsianReads) = remote(server, cached: "S1", inSwinsian: "S1")
    try await remote.play(trackIDs: [464, 465])
    #expect(server.requests.map(\.method) == ["NONCE", "HASH", "PUSH"])
    #expect(server.requests[0].headers["Device-UUID"] == SwinsianRemote.deviceUUID)
    #expect(server.requests[0].headers["Device-Name"] == "Clutter")
    #expect(server.requests[2].body == "[464,465]")
    #expect(server.requests.map { $0.headers["CSeq"] } == ["1", "2", "3"])
    #expect(swinsianReads.value == 0)
}

@Test func readsAndCachesSwinsiansSecretTheFirstTime() async throws {
    let server = FakeServer(acceptedSecret: "S1")
    let (remote, cache, _) = remote(server, cached: nil, inSwinsian: "S1")
    try await remote.play(trackIDs: [1])
    #expect(cache.value == "S1")
    #expect(server.requests.last?.method == "PUSH")
}

@Test func aRejectedCachedSecretIsReplacedBySwinsiansOnANewConnection() async throws {
    let server = FakeServer(acceptedSecret: "S2")
    let (remote, cache, _) = remote(server, cached: "S1", inSwinsian: "S2")
    try await remote.play(trackIDs: [1])
    #expect(cache.value == "S2")
    #expect(server.connections == 2)
    #expect(server.requests.map(\.method) == ["NONCE", "HASH", "NONCE", "HASH", "PUSH"])
}

@Test func failsWhenNoSecretIsAccepted() async {
    let server = FakeServer(acceptedSecret: "S3")
    let (remote, _, _) = remote(server, cached: "S1", inSwinsian: "S2")
    await #expect(throws: SwinsianRemote.RemoteError.notAuthorized) { try await remote.play(trackIDs: [1]) }
    #expect(!server.requests.contains { $0.method == "PUSH" })
}

@Test func failsWhenThereIsNoSecretAtAll() async {
    let server = FakeServer(acceptedSecret: "S1")
    let (remote, _, _) = remote(server, cached: nil, inSwinsian: nil)
    await #expect(throws: SwinsianRemote.RemoteError.notAuthorized) { try await remote.play(trackIDs: [1]) }
}

/// Talks to the real Swinsian Remote server: `CLUTTER_LIVE_SWINSIAN=1 scripts/test.sh --filter liveSwinsian`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CLUTTER_LIVE_SWINSIAN"] != nil))
func liveSwinsianRemoteAnswersANonceAndTurnsDownAWrongSecret() async throws {
    let connection = try await NetworkSwinsianConnection.open()
    defer { connection.close() }
    let nonce = SwinsianRemote.makeNonce()
    let nonceReply = try await connection.send(SwinsianRemoteMessage.render(method: "NONCE", resource: "/", headers: [
        ("CSeq", "1"), ("Device-UUID", SwinsianRemote.deviceUUID), ("Device-Name", SwinsianRemote.deviceName), ("Nonce", nonce),
    ]))
    #expect(nonceReply.isOK)
    #expect(nonceReply.headers["Nonce"]?.count == 64)
    let hashReply = try await connection.send(SwinsianRemoteMessage.render(method: "HASH", resource: "/", headers: [
        ("CSeq", "2"), ("Hash", SwinsianRemote.proof(secret: "wrong", nonce: nonce)),
    ]))
    #expect(hashReply.headers["Hash"] == nil)
}
