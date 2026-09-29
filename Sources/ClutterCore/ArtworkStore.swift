import AppKit

/// Cover images, cached on disk as `<album id>.jpg`.
public struct ArtworkStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func image(for album: Album) -> NSImage? {
        NSImage(contentsOf: fileURL(for: album))
    }

    public func hasImage(for album: Album) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: album).path)
    }

    public func save(_ data: Data, for album: Album) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: album), options: .atomic)
    }

    /// Deletes cached covers whose album isn't in `artworkNames`.
    public func prune(keeping artworkNames: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" && !artworkNames.contains(file.deletingPathExtension().lastPathComponent) {
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                NSLog("Clutter: couldn't delete %@: %@", file.path, String(describing: error))
            }
        }
    }

    private func fileURL(for album: Album) -> URL {
        directory.appending(path: "\(album.artworkName).jpg")
    }
}
