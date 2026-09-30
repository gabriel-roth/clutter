import Foundation
import Testing
@testable import ClutterCore

private let album = Album(title: "Court and Spark", artist: "Joni Mitchell", uri: "spotify:album:2akjxkzFolkeV72Yyv5KrM", artworkName: "court-and-spark")

private func devices(_ entries: [(id: String, name: String, type: String)]) -> String {
    let list = entries.map { #"{"id":"\#($0.id)","name":"\#($0.name)","type":"\#($0.type)","is_active":false}"# }
    return #"{"devices":[\#(list.joined(separator: ","))]}"#
}

@MainActor private func makePlayer(_ http: FakeHTTP, launches: Box<Int> = Box(0)) -> WebAPISpotifyPlayer {
    WebAPISpotifyPlayer(
        library: SpotifyLibrary(accessToken: { "TOKEN" }, http: { try http.handle($0) }),
        machineNames: ["Gabriel’s MacBook Pro"],
        launchSpotify: { launches.value += 1 },
        sleep: { _ in }
    )
}

@MainActor @Test func playsOnThisMachinesDeviceNotOthers() async throws {
    let http = FakeHTTP([
        (200, devices([("phone", "iPhone", "Smartphone"), ("other", "Studio Mac", "Computer"), ("mine", "Gabriel's MacBook Pro", "Computer")])),
        (204, ""),
    ])
    try await makePlayer(http).start(album)
    #expect(http.recorded.count == 2)
    let play = http.recorded[1]
    #expect(play.httpMethod == "PUT")
    #expect(play.url?.absoluteString == "https://api.spotify.com/v1/me/player/play?device_id=mine")
    #expect(play.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(play.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } == ["context_uri": album.uri])
}

@MainActor @Test func launchesSpotifyHiddenOnceAndWaitsForItsDevice() async throws {
    let none = devices([("phone", "iPhone", "Smartphone")])
    let http = FakeHTTP([
        (200, none), (200, none),
        (200, devices([("mine", "Gabriel’s MacBook Pro", "Computer")])),
        (204, ""),
    ])
    let launches = Box(0)
    try await makePlayer(http, launches: launches).start(album)
    #expect(launches.value == 1)
    #expect(http.recorded.last?.url?.absoluteString == "https://api.spotify.com/v1/me/player/play?device_id=mine")
}

@MainActor @Test func givesUpWithoutPlayingElsewhereWhenThisMachineNeverAppears() async {
    let other = devices([("other", "Studio Mac", "Computer")])
    let http = FakeHTTP(Array(repeating: (200, other), count: WebAPISpotifyPlayer.pollAttempts))
    await #expect(throws: WebAPISpotifyPlayer.PlayError.noLocalDevice(seen: ["Studio Mac"])) {
        try await makePlayer(http).start(album)
    }
    #expect(http.recorded.allSatisfy { $0.httpMethod == "GET" })
}

@MainActor @Test func retriesWhileANewDeviceAnswersNotFound() async throws {
    let http = FakeHTTP([
        (200, devices([("mine", "Gabriel’s MacBook Pro", "Computer")])),
        (404, #"{"error":{"status":404,"message":"Device not found"}}"#),
        (204, ""),
    ])
    try await makePlayer(http).start(album)
    #expect(http.recorded.map(\.httpMethod) == ["GET", "PUT", "PUT"])
}
