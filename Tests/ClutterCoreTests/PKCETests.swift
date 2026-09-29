import Foundation
import Testing
@testable import ClutterCore

@Test func challengeMatchesTheRFC7636Example() {
    let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test func randomVerifierIs43Base64URLCharacters() {
    let verifier = PKCE().verifier
    #expect(verifier.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil, "\(verifier)")
}

@Test func randomVerifiersDiffer() {
    #expect(PKCE().verifier != PKCE().verifier)
}
