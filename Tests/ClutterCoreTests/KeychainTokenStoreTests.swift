import Foundation
import Testing
@testable import ClutterCore

private func makeStore() -> KeychainTokenStore {
    KeychainTokenStore(service: "com.gabrielroth.Clutter.tests.\(UUID().uuidString)")
}

private let tokens = SpotifyTokens(accessToken: "AT", refreshToken: "RT", expiresAt: Date(timeIntervalSince1970: 1_000_000))

@Test func emptyKeychainStoreLoadsNil() {
    #expect(makeStore().load() == nil)
}

@Test func savedTokensLoadBack() throws {
    let store = makeStore()
    defer { store.delete() }
    try store.save(tokens)
    #expect(store.load() == tokens)
}

@Test func savingAgainReplacesTheTokens() throws {
    let store = makeStore()
    defer { store.delete() }
    try store.save(tokens)
    var newer = tokens
    newer.accessToken = "NEWER"
    try store.save(newer)
    #expect(store.load() == newer)
}

@Test func deletedTokensAreGone() throws {
    let store = makeStore()
    try store.save(tokens)
    store.delete()
    #expect(store.load() == nil)
}

@Test func defaultKeychainItemIsClutters() {
    let store = KeychainTokenStore()
    #expect(store.service == "com.gabrielroth.Clutter.spotify")
    #expect(store.account == "tokens")
}
