import AppKit
import Testing
@testable import ClutterCore

private let hejira = SwinsianAlbum.album(title: "Hejira", artist: "Joni Mitchell")
private let spotifyAlbum = Album(title: "T", artist: "A", uri: "spotify:album:t", artworkName: "t")

@Test func quotesAppleScriptStrings() {
    #expect(AppleScriptText.quoted(#"Say "Hi" \o/"#) == #""Say \"Hi\" \\o/""#)
}

@Test func playScriptKeepsOnlyTheAlbumsTracksInTheQueue() {
    let script = SwinsianPlayer.playScript(for: SwinsianAlbum.album(title: #"The "Best""#, artist: "Me"))
    #expect(script.contains(#"delete (every track of playback queue whose album is not "The \"Best\"" or album artist or artist is not "Me")"#))
}

@MainActor
private func player(results: [String], running: Bool = true) -> (SwinsianPlayer, Box<[String]>, Box<Int>) {
    let scripts = Box<[String]>([]), launches = Box(0)
    let replies = Box(results)
    let isRunning = Box(running)
    let player = SwinsianPlayer(
        runScript: { script in
            scripts.value.append(script)
            return replies.value.isEmpty ? "" : replies.value.removeFirst()
        },
        isRunning: { isRunning.value },
        launch: {
            launches.value += 1
            isRunning.value = true
        },
        sleep: { _ in }
    )
    return (player, scripts, launches)
}

@MainActor @Test func playsARunningSwinsianWithoutLaunchingIt() async throws {
    let (player, scripts, launches) = player(results: ["ok"])
    try await player.start(hejira)
    #expect(launches.value == 0)
    #expect(scripts.value == [SwinsianPlayer.playScript(for: hejira)])
}

@MainActor @Test func aMissingAlbumInARunningSwinsianFailsAtOnce() async {
    let (player, scripts, _) = player(results: ["missing", "ok"])
    await #expect(throws: SwinsianPlayer.PlayError.albumNotFound) { try await player.start(hejira) }
    #expect(scripts.value.count == 1)
}

@MainActor @Test func launchesSwinsianAndRetriesWhileItLoads() async throws {
    let (player, scripts, launches) = player(results: ["", "missing", "ok"], running: false)
    try await player.start(hejira)
    #expect(launches.value == 1)
    #expect(scripts.value.count == 3)
}

@MainActor @Test func routesEachAlbumToItsOwnApp() {
    let spotify = SpyPlayer(), swinsian = SpyPlayer()
    let router = RoutingPlayer(spotify: spotify, swinsian: swinsian)
    router.play(hejira)
    router.play(spotifyAlbum)
    #expect(spotify.played == [spotifyAlbum])
    #expect(swinsian.played == [hejira])
}

@Test(arguments: [
    ("playing", "playing", CurrentAlbumSource.swinsian),
    ("playing", "paused", .spotify),
    ("paused", "playing", .swinsian),
    ("paused", "paused", .spotify),
    ("stopped", "paused", .swinsian),
    ("stopped", "stopped", .spotify),
    ("", "", .spotify),
])
func choosesWhichAppToAddFrom(spotify: String, swinsian: String, expected: CurrentAlbumSource) {
    #expect(CurrentAlbumSource.choose(spotifyState: spotify, swinsianState: swinsian) == expected)
}

@Test func stateScriptsDoNotLaunchTheApps() {
    #expect(CurrentAlbumSource.stateScript(for: "Spotify").hasPrefix(#"if application "Spotify" is running then"#))
    #expect(SwinsianNowPlaying.script.hasPrefix(#"if application "Swinsian" is running then"#))
}

private func descriptor(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
    let list = NSAppleEventDescriptor.list()
    for (index, item) in items.enumerated() { list.insert(item, at: index + 1) }
    return list
}

@Test func readsSwinsiansCurrentAlbumAndArt() {
    let art = jpegData()
    let reply = descriptor([.init(string: "Hejira"), .init(string: "Joni Mitchell"), NSAppleEventDescriptor(descriptorType: 0x7350_6963, data: art)!])
    let playing = SwinsianNowPlaying.parse(reply)
    #expect(playing == SwinsianNowPlaying(album: hejira, artwork: art))
}

@Test func swinsianAlbumWithoutArtHasNoArtwork() {
    let reply = descriptor([.init(string: "Hejira"), .init(string: "Joni Mitchell"), NSAppleEventDescriptor(typeCode: 0x6D73_6E67)])  // missing value
    #expect(SwinsianNowPlaying.parse(reply) == SwinsianNowPlaying(album: hejira, artwork: nil))
}

@Test func nothingPlayingOrNoAlbumTitleIsNotAnAlbum() {
    #expect(SwinsianNowPlaying.parse(descriptor([])) == nil)
    #expect(SwinsianNowPlaying.parse(nil) == nil)
    #expect(SwinsianNowPlaying.parse(descriptor([.init(string: ""), .init(string: "Joni Mitchell"), NSAppleEventDescriptor(typeCode: 0x6D73_6E67)])) == nil)
}
