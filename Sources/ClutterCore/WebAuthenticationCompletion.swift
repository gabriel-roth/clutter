import Foundation

/// Builds the completion handler for a web authentication session. It is deliberately not tied to any
/// actor: AuthenticationServices calls it on an XPC queue, and it only resumes the continuation, at most once.
public func webAuthenticationCompletion(resuming continuation: CheckedContinuation<URL, Error>) -> @Sendable (URL?, Error?) -> Void {
    let resumed = OnceFlag()
    return { url, error in
        guard resumed.claim() else { return }
        if let url {
            continuation.resume(returning: url)
        } else {
            continuation.resume(throwing: error ?? SpotifyAuthError.missingCode)
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
