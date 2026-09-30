import AppKit
import CryptoKit

/// Albums from the Swinsian app, which are named by album artist and title since Swinsian has no album IDs.
public enum SwinsianAlbum {
    static let uriPrefix = "swinsian:album:"
    static let bundleIdentifier = "com.swinsian.Swinsian"

    /// Checked before any script mentions Swinsian: compiling one on a Mac without it asks where it is.
    public static func appIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// `artist` is the album artist, or the track artist when the album has none.
    public static func album(title: String, artist: String) -> Album {
        let digest = SHA256.hash(data: Data("\(artist)\n\(title)".utf8))
        let key = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return Album(title: title, artist: artist, uri: uriPrefix + key, artworkName: "swinsian-" + key)
    }

    public static func isSwinsian(_ album: Album) -> Bool {
        album.uri.hasPrefix(uriPrefix)
    }
}

/// The Swinsian albums added to Clutter, saved as JSON. Unlike Spotify's, this list is Clutter's own:
/// adding and removing albums here never touches Swinsian's library.
public struct SwinsianLibrary: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Newest first. Empty when nothing has been added or the file can't be read; an unreadable
    /// file is moved aside so a later save can't destroy it.
    public func albums() -> [SavedAlbum] {
        load().sorted { $0.addedAt > $1.addedAt }.map { SavedAlbum(album: $0.album, addedAt: $0.addedAt, artworkURL: nil) }
    }

    /// Adds the album, or makes it the newest if it's already here.
    public func add(_ album: Album, at date: Date = .now) {
        save(load().filter { $0.album.uri != album.uri } + [Record(album: album, addedAt: date)])
    }

    public func remove(uri: String) {
        save(load().filter { $0.album.uri != uri })
    }

    private struct Record: Codable {
        let album: Album
        let addedAt: Date
    }

    private func load() -> [Record] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try JSONDecoder().decode([Record].self, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("Clutter: couldn't read %@: %@", fileURL.path, String(describing: error))
            LibraryStore.moveAsideUnreadableFile(at: fileURL)
            return []
        }
    }

    private func save(_ records: [Record]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Clutter: couldn't save %@: %@", fileURL.path, String(describing: error))
        }
    }
}
