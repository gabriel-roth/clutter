import Foundation
import Network

/// A TLS connection to the Swinsian Remote server on this Mac, found through Bonjour. Only the loopback
/// interface is used, so a Swinsian on another computer is never reached.
final class NetworkSwinsianConnection: SwinsianRemoteConnection, @unchecked Sendable {
    enum NetworkError: Error {
        case serverNotFound
        case timedOut
        case closed
    }

    static let serviceType = "_swinsianremote._tcp"
    static let timeout: DispatchTimeInterval = .seconds(5)

    private let connection: NWConnection
    private let queue: DispatchQueue
    /// Bytes received but not yet parsed. Touched only on `queue`.
    private var buffer = Data()

    private init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Finds the server and connects. Throws if Swinsian Remote isn't running or doesn't answer in time.
    static func open() async throws -> NetworkSwinsianConnection {
        let queue = DispatchQueue(label: "Clutter.SwinsianRemote")
        let endpoint = try await findServer(queue: queue)
        // Swinsian's certificate is one it made for itself, so there's nothing to check it against.
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
        let parameters = NWParameters(tls: tls)
        parameters.requiredInterfaceType = .loopback
        let connection = NWConnection(to: endpoint, using: parameters)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let once = Once(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(with: .success(()))
                case .failed(let error), .waiting(let error): once.resume(with: .failure(error))
                case .cancelled: once.resume(with: .failure(NetworkError.closed))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { once.resume(with: .failure(NetworkError.timedOut)) }
        }
        connection.stateUpdateHandler = nil
        return NetworkSwinsianConnection(connection: connection, queue: queue)
    }

    private static func findServer(queue: DispatchQueue) async throws -> NWEndpoint {
        let parameters = NWParameters()
        parameters.requiredInterfaceType = .loopback
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: parameters)
        defer { browser.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            browser.browseResultsChangedHandler = { results, _ in
                if let result = results.first { once.resume(with: .success(result.endpoint)) }
            }
            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state { once.resume(with: .failure(error)) }
            }
            browser.start(queue: queue)
            // Bonjour answers for this Mac at once, so a short wait means the server isn't there.
            queue.asyncAfter(deadline: .now() + .seconds(2)) { once.resume(with: .failure(NetworkError.serverNotFound)) }
        }
    }

    func send(_ request: Data) async throws -> SwinsianRemoteMessage.Reply {
        try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            queue.async { [self] in
                connection.send(content: request, completion: .contentProcessed { [self] error in
                    if let error { return once.resume(with: .failure(error)) }
                    receiveReply(once)
                })
                queue.asyncAfter(deadline: .now() + Self.timeout) { once.resume(with: .failure(NetworkError.timedOut)) }
            }
        }
    }

    /// Reads until a whole message is buffered. Runs on `queue`.
    private func receiveReply(_ once: Once<SwinsianRemoteMessage.Reply>) {
        if let (reply, used) = SwinsianRemoteMessage.parse(buffer) {
            buffer.removeFirst(used)
            return once.resume(with: .success(reply))
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            if let error { return once.resume(with: .failure(error)) }
            if isComplete && SwinsianRemoteMessage.parse(buffer) == nil { return once.resume(with: .failure(NetworkError.closed)) }
            receiveReply(once)
        }
    }

    func close() {
        connection.cancel()
    }
}

/// Resumes a continuation the first time only, so a timeout and a late answer can't both resume it.
private final class Once<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Value, any Error>) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}
