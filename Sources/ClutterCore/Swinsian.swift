import AppKit

/// Plays albums in Swinsian without bringing it to the front, starting it hidden if it isn't running.
///
/// Swinsian's AppleScript can't play a given track or add to the playback queue, but it can delete
/// from the queue, and playing an empty queue fills it from whatever Swinsian's window is showing. So
/// the queue is emptied and refilled (muted, stopped at once), everything not on the album is deleted,
/// and what's left plays, in the order of Swinsian's current view.
public struct SwinsianPlayer: AlbumPlayer {
    private let runScript: @Sendable (String) async -> String
    private let isRunning: @Sendable () -> Bool
    private let launch: @Sendable () -> Void
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        runScript: @escaping @Sendable (String) async -> String = Self.runAppleScript,
        isRunning: @escaping @Sendable () -> Bool = SwinsianAlbum.appIsRunning,
        launch: @escaping @Sendable () -> Void = Self.launchSwinsianInBackground,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.runScript = runScript
        self.isRunning = isRunning
        self.launch = launch
        self.sleep = sleep
    }

    public func play(_ album: Album) {
        Task {
            do {
                try await start(album)
            } catch {
                NSLog("Clutter: couldn't play %@ in Swinsian: %@", album.title, String(describing: error))
                NSSound.beep()
            }
        }
    }

    enum PlayError: Error, Equatable {
        /// Swinsian's current view has none of the album's tracks, or Swinsian never answered.
        case albumNotFound
    }

    /// A Swinsian that's just started takes a moment to answer and to load its library.
    static let launchAttempts = 15

    func start(_ album: Album) async throws {
        let launched = !isRunning()
        if launched { launch() }
        let attempts = launched ? Self.launchAttempts : 1
        for attempt in 1...attempts {
            if await runScript(Self.playScript(for: album)) == "ok" { return }
            if attempt < attempts { try await sleep(.seconds(1)) }
        }
        throw PlayError.albumNotFound
    }

    /// Returns "ok" once the album is playing, or "missing" if none of its tracks are in the current view.
    nonisolated static func playScript(for album: Album) -> String {
        """
        tell application "Swinsian"
            set savedVolume to sound volume
            try
                stop
                delete every track of playback queue
                set sound volume to 0
                play
                stop
                delete (every track of playback queue whose album is not \(AppleScriptText.quoted(album.title)) or album artist or artist is not \(AppleScriptText.quoted(album.artist)))
                set sound volume to savedVolume
            on error message number code
                set sound volume to savedVolume
                error message number code
            end try
            if (count of tracks of playback queue) is 0 then return "missing"
            play
            return "ok"
        end tell
        """
    }

    public static let runAppleScript: @Sendable (String) async -> String = { await AppleScriptRunner.run($0) }

    /// `open -g -j` starts the app without activating or showing it.
    public static let launchSwinsianInBackground: @Sendable () -> Void = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-j", "-b", SwinsianAlbum.bundleIdentifier]
        try? process.run()
    }
}

/// The album Swinsian is playing or paused on, and its cover, as read through Swinsian's AppleScript.
public struct SwinsianNowPlaying: Equatable, Sendable {
    public let album: Album
    /// JPEG or PNG data, or nil when the album has no art.
    public let artwork: Data?

    /// Returns {album, album artist or artist, album art} of the current track, or {} when Swinsian
    /// isn't running or is stopped. Never launches Swinsian.
    public static let script = """
        if application "Swinsian" is running then
            tell application "Swinsian"
                if player state is not stopped then
                    set t to current track
                    return {album of t, album artist or artist of t, album art of t}
                end if
            end tell
        end if
        return {}
        """

    /// Nil unless the reply names an album.
    public static func parse(_ reply: NSAppleEventDescriptor?) -> SwinsianNowPlaying? {
        guard let reply, reply.numberOfItems >= 3,
              let title = reply.atIndex(1)?.stringValue, !title.isEmpty else { return nil }
        let artist = reply.atIndex(2)?.stringValue ?? ""
        // Missing art comes back as `missing value`, which isn't an image.
        let artwork = reply.atIndex(3).map(\.data).flatMap { NSBitmapImageRep(data: $0) != nil ? $0 : nil }
        return SwinsianNowPlaying(album: SwinsianAlbum.album(title: title, artist: artist), artwork: artwork)
    }

    /// What Swinsian is playing, or nil if it isn't playing an album.
    public static func fetch() async -> SwinsianNowPlaying? {
        await AppleScriptRunner.run(script, parse: parse)
    }
}
