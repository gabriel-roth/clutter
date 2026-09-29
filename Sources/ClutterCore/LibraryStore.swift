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

    /// Nil when nothing has been saved yet, or the file can't be read.
    public func load() -> Library? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(Library.self, from: Data(contentsOf: fileURL))
        } catch {
            NSLog("Clutter: couldn't read %@: %@", fileURL.path, String(describing: error))
            return nil
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
