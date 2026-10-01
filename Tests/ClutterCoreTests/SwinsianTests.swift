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
        remoteEnabled: { false },
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

private func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor { descriptor(items) }
private var missing: NSAppleEventDescriptor { NSAppleEventDescriptor(typeCode: 0x6D73_6E67) }

@Test func trackIDsComeBackInDiscAndTrackOrder() {
    let reply = list([
        list([.init(string: "12"), .init(string: "10"), .init(string: "11"), .init(string: "13")]),
        list([.init(int32: 2), .init(int32: 1), .init(int32: 1), .init(int32: 2)]),
        list([.init(int32: 1), .init(int32: 2), .init(int32: 1), .init(int32: 2)]),
    ])
    #expect(SwinsianTracks.parseIDs(reply) == [11, 10, 12, 13])
}

@Test func tracksWithoutDiscNumbersSortByTrack() {
    let reply = list([
        list([.init(string: "2"), .init(string: "1")]),
        list([missing, missing]),
        list([.init(int32: 2), .init(int32: 1)]),
    ])
    #expect(SwinsianTracks.parseIDs(reply) == [1, 2])
}

@Test func noTracksOrNoReplyMeansNoIDs() {
    #expect(SwinsianTracks.parseIDs(list([list([]), list([]), list([])])) == [])
    #expect(SwinsianTracks.parseIDs(nil) == [])
}

@Test func trackScriptMatchesTheAlbumsTitleAndArtist() {
    let script = SwinsianTracks.script(for: SwinsianAlbum.album(title: #"The "Best""#, artist: "Me"))
    #expect(script.contains(#"whose album is "The \"Best\"" and album artist or artist is "Me")"#))
}

@MainActor
private func remotePlayer(ids: [[Int]], remoteFails: Bool = false, enabled: Bool = true, running: Bool = true)
    -> (SwinsianPlayer, played: Box<[[Int]]>, scripts: Box<[String]>, lookups: Box<Int>) {
    let played = Box<[[Int]]>([]), scripts = Box<[String]>([]), lookups = Box(0)
    let answers = Box(ids), isRunning = Box(running)
    let player = SwinsianPlayer(
        runScript: { script in
            scripts.value.append(script)
            return "ok"
        },
        isRunning: { isRunning.value },
        launch: { isRunning.value = true },
        remoteEnabled: { enabled },
        trackIDs: { _ in
            lookups.value += 1
            return answers.value.count > 1 ? answers.value.removeFirst() : answers.value.first ?? []
        },
        playRemotely: { trackIDs in
            played.value.append(trackIDs)
            if remoteFails { throw SwinsianRemote.RemoteError.notAuthorized }
        },
        sleep: { _ in }
    )
    return (player, played, scripts, lookups)
}

@MainActor @Test func playsThroughSwinsianRemoteWhenItsOn() async throws {
    let (player, played, scripts, _) = remotePlayer(ids: [[464, 465]])
    try await player.start(hejira)
    #expect(played.value == [[464, 465]])
    #expect(scripts.value.isEmpty)
}

@MainActor @Test func fallsBackToAppleScriptWhenSwinsianRemoteFails() async throws {
    let (player, played, scripts, _) = remotePlayer(ids: [[464]], remoteFails: true)
    try await player.start(hejira)
    #expect(played.value == [[464]])
    #expect(scripts.value == [SwinsianPlayer.playScript(for: hejira)])
}

@MainActor @Test func usesAppleScriptAloneWhenSwinsianRemoteIsOff() async throws {
    let (player, played, scripts, lookups) = remotePlayer(ids: [[464]], enabled: false)
    try await player.start(hejira)
    #expect(played.value.isEmpty)
    #expect(lookups.value == 0)
    #expect(scripts.value == [SwinsianPlayer.playScript(for: hejira)])
}

@MainActor @Test func anAlbumWithNoTracksInSwinsianIsNotPlayedAtAll() async {
    let (player, played, scripts, _) = remotePlayer(ids: [[]])
    await #expect(throws: SwinsianPlayer.PlayError.albumNotFound) { try await player.start(hejira) }
    #expect(played.value.isEmpty)
    #expect(scripts.value.isEmpty)
}

@MainActor @Test func aJustLaunchedSwinsianIsAskedForTracksUntilItAnswers() async throws {
    let (player, played, _, lookups) = remotePlayer(ids: [[], [], [464]], running: false)
    try await player.start(hejira)
    #expect(lookups.value == 3)
    #expect(played.value == [[464]])
}
