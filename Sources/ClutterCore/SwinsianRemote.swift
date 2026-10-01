import CryptoKit
import Foundation

/// The text messages of the Swinsian Remote protocol: a request line (`METHOD resource SWN/1.0`) or
/// status line (`SWN/1.0 200 OK`), headers, a blank line, and a body as long as its Content-Length.
public enum SwinsianRemoteMessage {
    public struct Reply: Equatable, Sendable {
        /// The first line: a status line, or a request line when Swinsian pushes something unasked.
        public let status: String
        public let headers: [String: String]
        public let body: Data

        public var isOK: Bool { status.hasPrefix("SWN/1.0 200") }
    }

    static func render(method: String, resource: String, headers: [(String, String)], body: Data = Data()) -> Data {
        var head = "\(method) \(resource) SWN/1.0\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        if !body.isEmpty {
            head += "Content-Length: \(body.count)\r\n"
        }
        return Data((head + "\r\n").utf8) + body
    }

    /// The first whole message in `buffer` and how many bytes it took, or nil until one has arrived.
    static func parse(_ buffer: Data) -> (Reply, used: Int)? {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["Content-Length"] ?? "") ?? 0
        guard buffer.endIndex - end.upperBound >= length else { return nil }
        let body = Data(buffer[end.upperBound..<end.upperBound + length])
        return (Reply(status: lines[0], headers: headers, body: body), end.upperBound + length - buffer.startIndex)
    }
}

/// A connection to Swinsian's Remote server that sends one request at a time and waits for its reply.
public protocol SwinsianRemoteConnection: Sendable {
    func send(_ request: Data) async throws -> SwinsianRemoteMessage.Reply
    func close()
}

/// Plays tracks through Swinsian Remote, the server Swinsian runs for its iPhone remote app (turned on
/// in Swinsian's Remote settings, a tab hidden unless `ShowRemotePreferences` is set). Unlike
/// AppleScript it can replace the queue with given tracks, without touching Swinsian's window.
///
/// Clutter signs in as a device of its own. Swinsian adds a device the first time it connects and
/// makes it a secret, which it keeps in the keychain; Clutter reads that once (macOS asks the user)
/// and keeps a copy. Each connection proves the secret with an HMAC of a nonce.
public struct SwinsianRemote: Sendable {
    /// Where the device's secret comes from.
    public struct Secrets: Sendable {
        /// Clutter's own copy.
        let cached: @Sendable () -> String?
        let cache: @Sendable (String) -> Void
        /// Read from Swinsian's keychain item, which can make macOS ask the user first.
        let fromSwinsian: @Sendable () async -> String?

        public init(
            cached: @escaping @Sendable () -> String?,
            cache: @escaping @Sendable (String) -> Void,
            fromSwinsian: @escaping @Sendable () async -> String?
        ) {
            self.cached = cached
            self.cache = cache
            self.fromSwinsian = fromSwinsian
        }
    }

    public enum RemoteError: Error, Equatable {
        /// No secret Clutter could find was accepted.
        case notAuthorized
        case unexpectedReply(String)
    }

    /// Clutter's device, as listed under Allowed Devices in Swinsian's Remote settings.
    static let deviceUUID = "6C0B7E2A-3F1D-4C55-9E8B-C1A77E5D0001"
    static let deviceName = "Clutter"

    private let connect: @Sendable () async throws -> any SwinsianRemoteConnection
    private let secrets: Secrets

    public init(
        connect: @escaping @Sendable () async throws -> any SwinsianRemoteConnection = Self.connectOverNetwork,
        secrets: Secrets = .keychain
    ) {
        self.connect = connect
        self.secrets = secrets
    }

    public static let connectOverNetwork: @Sendable () async throws -> any SwinsianRemoteConnection = { try await NetworkSwinsianConnection.open() }

    /// Replaces Swinsian's queue with the tracks, by Swinsian track ID, and plays them in order.
    public func play(trackIDs: [Int]) async throws {
        let session = try await signIn()
        defer { session.connection.close() }
        let body = Data("[\(trackIDs.map(String.init).joined(separator: ","))]".utf8)
        // Swinsian answers by pushing its new playback state rather than with a status line.
        let reply = try await session.send("PUSH", "play_tracks", body: body)
        if reply.status.hasPrefix("SWN/1.0 4") { throw RemoteError.unexpectedReply(reply.status) }
    }

    /// Tries Clutter's copy of the secret, then, if that's missing or turned down, Swinsian's own.
    private func signIn() async throws -> Session {
        var secret = secrets.cached()
        var readSwinsian = false
        while true {
            let session = Session(connection: try await connect())
            let nonce = Self.makeNonce()
            let nonceReply = try await session.send("NONCE", "/", headers: [
                ("Device-UUID", Self.deviceUUID), ("Device-Name", Self.deviceName), ("Nonce", nonce),
            ])
            guard nonceReply.isOK else {
                session.connection.close()
                throw RemoteError.unexpectedReply(nonceReply.status)
            }
            if secret == nil && !readSwinsian {
                secret = await secrets.fromSwinsian()
                readSwinsian = true
            }
            guard let tried = secret else {
                session.connection.close()
                throw RemoteError.notAuthorized
            }
            let hashReply = try await session.send("HASH", "/", headers: [("Hash", Self.proof(secret: tried, nonce: nonce))])
            // A wrong proof still gets 200 OK, but only a right one gets Swinsian's own Hash back.
            if hashReply.isOK && hashReply.headers["Hash"] != nil {
                if readSwinsian { secrets.cache(tried) }
                return session
            }
            session.connection.close()
            guard !readSwinsian else { throw RemoteError.notAuthorized }
            secret = await secrets.fromSwinsian()
            readSwinsian = true
            // Swinsian's secret is the same one that was just turned down.
            if secret == tried { throw RemoteError.notAuthorized }
        }
    }

    /// Numbers each request on a connection.
    private final class Session {
        let connection: any SwinsianRemoteConnection
        private var cseq = 0

        init(connection: any SwinsianRemoteConnection) {
            self.connection = connection
        }

        func send(_ method: String, _ resource: String, headers: [(String, String)] = [], body: Data = Data()) async throws -> SwinsianRemoteMessage.Reply {
            cseq += 1
            let request = SwinsianRemoteMessage.render(method: method, resource: resource, headers: [("CSeq", "\(cseq)")] + headers, body: body)
            return try await connection.send(request)
        }
    }

    /// The HMAC-SHA512 of the nonce, keyed by the secret, as uppercase hex.
    static func proof(secret: String, nonce: String) -> String {
        let mac = HMAC<SHA512>.authenticationCode(for: Data(nonce.utf8), using: SymmetricKey(data: Data(secret.utf8)))
        return mac.map { String(format: "%02X", $0) }.joined()
    }

    /// 32 random bytes as 64 hex characters, the length Swinsian requires.
    static func makeNonce() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02X", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }

    /// Whether Swinsian Remote is turned on in Swinsian's settings.
    public static func isEnabled() -> Bool {
        let app = "com.swinsian.Swinsian" as CFString
        CFPreferencesAppSynchronize(app)
        return CFPreferencesCopyAppValue("AllowSwinsianRemote" as CFString, app) as? Bool ?? false
    }
}

extension SwinsianRemote.Secrets {
    /// Clutter's copy lives in its own keychain item; Swinsian's is the one it made for Clutter's device.
    public static let keychain = SwinsianRemote.Secrets(
        cached: { cachedItem.load().map { String(decoding: $0, as: UTF8.self) } },
        cache: { secret in
            do {
                try cachedItem.save(Data(secret.utf8))
            } catch {
                NSLog("Clutter: couldn't save the Swinsian Remote secret: %@", String(describing: error))
            }
        },
        fromSwinsian: {
            // Off the cooperative pool: macOS may block this until the user answers its dialog.
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let item = KeychainItem(service: "Swinsian Remote", account: SwinsianRemote.deviceUUID)
                    continuation.resume(returning: item.load().map { String(decoding: $0, as: UTF8.self) })
                }
            }
        }
    )

    private static let cachedItem = KeychainItem(service: "com.gabrielroth.Clutter.swinsian-remote", account: SwinsianRemote.deviceUUID)
}
