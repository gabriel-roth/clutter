import AppKit

/// Cover images: downloaded artwork on disk first, then the starter covers in the app bundle.
public struct ArtworkStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func image(for album: Album) -> NSImage? {
        NSImage(contentsOf: fileURL(for: album)) ?? Bundle.main.image(forResource: album.artworkName)
    }

    public func save(_ data: Data, for album: Album) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: album), options: .atomic)
    }

    private func fileURL(for album: Album) -> URL {
        directory.appending(path: "\(album.artworkName).jpg")
    }
}
