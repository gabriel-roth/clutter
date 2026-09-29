import AppKit
import AuthenticationServices
import ClutterCore

/// At launch, asks to connect to Spotify when Clutter has no saved sign-in, then runs the sign-in
/// in the system's web authentication sheet.
@MainActor
final class SpotifySignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let auth: SpotifyAuth
    private var session: ASWebAuthenticationSession?

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    func promptIfSignedOut() async {
        guard await !auth.isSignedIn else { return }
        let alert = NSAlert()
        alert.messageText = "Connect Clutter to Spotify"
        alert.informativeText = "Sign in so Clutter can see the albums in your Spotify library."
        alert.addButton(withTitle: "Sign In…")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try await auth.signIn { url in try await self.authorize(url) }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the sign-in window.
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't sign in to Spotify"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    private func authorize(_ url: URL) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let completion = webAuthenticationCompletion(resuming: continuation)
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: SpotifyAuthConfig.clutter.callbackScheme, completionHandler: completion)
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                completion(nil, ASWebAuthenticationSessionError(.presentationContextNotProvided))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.windows.first { $0.isVisible } ?? ASPresentationAnchor()
        }
    }
}
