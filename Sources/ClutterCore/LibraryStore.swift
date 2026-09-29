import Foundation

/// Saves the library as JSON.
public struct LibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// ~/Library/Application Support/Clutter
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Clutter", directoryHint: .isDirectory)
    }

    /// Nil when nothing has been saved yet, or the file can't be read. An unreadable file is moved
    /// aside to `library.json.unreadable` (replacing an earlier one) so a later save can't destroy it.
    public func load() -> Library? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(Library.self, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("Clutter: couldn't read %@: %@", fileURL.path, String(describing: error))
            moveAsideUnreadableFile()
            return nil
        }
    }

    private func moveAsideUnreadableFile() {
        let aside = fileURL.deletingLastPathComponent().appending(path: fileURL.lastPathComponent + ".unreadable")
        do {
            if FileManager.default.fileExists(atPath: aside.path) {
                try FileManager.default.removeItem(at: aside)
            }
            try FileManager.default.moveItem(at: fileURL, to: aside)
            NSLog("Clutter: moved the unreadable library to %@", aside.path)
        } catch {
            NSLog("Clutter: couldn't move %@ aside: %@", fileURL.path, String(describing: error))
        }
    }

    public func save(_ library: Library) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(library).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Clutter: couldn't save %@: %@", fileURL.path, String(describing: error))
        }
    }
}
