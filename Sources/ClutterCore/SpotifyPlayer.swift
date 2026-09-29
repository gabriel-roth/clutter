import Foundation

@MainActor
public protocol SpotifyPlayer {
    func play(_ album: Album)
}

/// Plays albums through Spotify's Web API, always on the Spotify app running on this Mac, and never
/// brings that app to the front (its AppleScript and URL commands do).
public struct WebAPISpotifyPlayer: SpotifyPlayer {
    private let library: SpotifyLibrary
    private let machineNames: [String]
    private let launchSpotify: @Sendable () -> Void
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        library: SpotifyLibrary,
        machineNames: [String] = Self.thisMachineNames(),
        launchSpotify: @escaping @Sendable () -> Void = Self.launchSpotifyInBackground,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.library = library
        self.machineNames = machineNames
        self.launchSpotify = launchSpotify
        self.sleep = sleep
    }

    public func play(_ album: Album) {
        Task {
            do {
                try await start(album)
            } catch {
                NSLog("Clutter: couldn't play %@: %@", album.title, String(describing: error))
            }
        }
    }

    enum PlayError: Error, Equatable {
        /// Spotify never listed a device named like this Mac; `seen` are the devices it did list.
        case noLocalDevice(seen: [String])
    }

    static let pollAttempts = 15
    static let playAttempts = 5

    func start(_ album: Album) async throws {
        let device = try await localDevice()
        // A device that's just appeared can answer 404 for a moment before it accepts playback.
        for attempt in 1...Self.playAttempts {
            do {
                return try await library.play(albumURI: album.spotifyURI, deviceID: device)
            } catch SpotifyLibraryError.requestFailed(404, _, _) where attempt < Self.playAttempts {
                try await sleep(.seconds(1))
            }
        }
    }

    /// The ID of this Mac's Spotify app. If it isn't running, starts it hidden and waits for it to appear.
    private func localDevice() async throws -> String {
        var launched = false
        var seen: [String] = []
        for attempt in 1...Self.pollAttempts {
            let devices = try await library.devices()
            seen = devices.map(\.name)
            if let id = devices.first(where: isThisMachine)?.id { return id }
            if !launched {
                launched = true
                launchSpotify()
            }
            if attempt < Self.pollAttempts { try await sleep(.seconds(1)) }
        }
        throw PlayError.noLocalDevice(seen: seen)
    }

    private func isThisMachine(_ device: SpotifyDevice) -> Bool {
        device.type == "Computer" && machineNames.contains { Self.normalized($0) == Self.normalized(device.name) }
    }

    private static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "\u{2019}", with: "'").lowercased()
    }

    /// The names Spotify's desktop app might use for this Mac: the computer name, and the host name without ".local".
    public static func thisMachineNames() -> [String] {
        var names = [Host.current().localizedName, ProcessInfo.processInfo.hostName].compactMap { $0 }
        names = names.map { $0.hasSuffix(".local") ? String($0.dropLast(".local".count)) : $0 }
        return Array(Set(names))
    }

    /// `open -g -j` starts the app without activating or showing it.
    public static let launchSpotifyInBackground: @Sendable () -> Void = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-j", "-a", "Spotify"]
        try? process.run()
    }
}
