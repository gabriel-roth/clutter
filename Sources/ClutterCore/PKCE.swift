import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636): lets Clutter sign in to Spotify without a client secret.
public struct PKCE: Sendable {
    public let verifier: String

    public init(verifier: String = PKCE.randomString()) {
        self.verifier = verifier
    }

    public var challenge: String {
        Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// 32 random bytes, base64url-encoded: 43 URL-safe characters.
    public static func randomString() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
