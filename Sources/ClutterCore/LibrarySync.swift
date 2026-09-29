import Foundation

/// Fetches the most recently saved albums, caches their covers, and shows them on the desktop.
/// Only the latest refresh counts: starting one cancels any still running.
@MainActor
public final class LibrarySync {
    private let library: SpotifyLibrary
    private let artwork: ArtworkStore
    private let controller: ClutterController
    private let albumCount: @MainActor () -> Int
    private let download: @Sendable (URL) async throws -> Data
    private var running: Task<Void, Never>?

    public init(
        library: SpotifyLibrary,
        artwork: ArtworkStore,
        controller: ClutterController,
        albumCount: @escaping @MainActor () -> Int,
        download: @escaping @Sendable (URL) async throws -> Data = LibrarySync.liveDownload
    ) {
        self.library = library
        self.artwork = artwork
        self.controller = controller
        self.albumCount = albumCount
        self.download = download
    }

    public static let liveDownload: @Sendable (URL) async throws -> Data = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// On failure the desktop is left as it was, and the reason is logged.
    @discardableResult
    public func refresh() -> Task<Void, Never> {
        running?.cancel()
        let count = albumCount()
        let task = Task { [library, artwork, download, controller] in
            do {
                let saved = try await library.recentAlbums(count: count)
                await withTaskGroup(of: Void.self) { group in
                    for item in saved where !artwork.hasImage(for: item.album) {
                        guard let url = item.artworkURL else { continue }
                        group.addTask {
                            do {
                                try artwork.save(try await download(url), for: item.album)
                            } catch {
                                NSLog("Clutter: couldn't download the cover of %@: %@", item.album.title, String(describing: error))
                            }
                        }
                    }
                }
                guard !Task.isCancelled else { return }
                controller.apply(saved.map(\.album))
                artwork.prune(keeping: Set(saved.map(\.album.artworkName)))
            } catch {
                guard !Task.isCancelled else { return }
                NSLog("Clutter: couldn't read the Spotify library: %@", String(describing: error))
            }
        }
        running = task
        return task
    }
}
