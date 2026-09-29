import Foundation

/// Fetches the most recently saved albums, caches their covers, and shows them on the desktop.
/// Only the latest refresh counts: starting one cancels any still running. Polling refreshes
/// whenever the library changes.
@MainActor
public final class LibrarySync {
    private let library: SpotifyLibrary
    private let artwork: ArtworkStore
    private let controller: ClutterController
    private let albumCount: @MainActor () -> Int
    private let download: @Sendable (URL) async throws -> Data
    private let sleep: @Sendable (Duration) async throws -> Void
    private var running: Task<Void, Never>?
    private var refreshesUnderway = 0
    /// The ETag of the library version the desktop last caught up to through `refreshIfChanged`.
    private var libraryETag: String?

    public init(
        library: SpotifyLibrary,
        artwork: ArtworkStore,
        controller: ClutterController,
        albumCount: @escaping @MainActor () -> Int,
        download: @escaping @Sendable (URL) async throws -> Data = LibrarySync.liveDownload,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.library = library
        self.artwork = artwork
        self.controller = controller
        self.albumCount = albumCount
        self.download = download
        self.sleep = sleep
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
        refresh(thenRemembering: nil)
    }

    /// Refreshes only if the library changed since the last refresh this started, which costs one
    /// small request, or none of the body when nothing changed. Does nothing while another refresh
    /// is underway, so it never cancels one a caller is waiting on.
    public func refreshIfChanged() async {
        guard refreshesUnderway == 0 else { return }
        let check: LibraryCheck
        do {
            check = try await library.checkForChanges(since: libraryETag)
        } catch {
            NSLog("Clutter: couldn't check the Spotify library for changes: %@", String(describing: error))
            return
        }
        guard case .changed(let etag) = check, refreshesUnderway == 0 else { return }
        await refresh(thenRemembering: etag).value
    }

    /// Calls `refreshIfChanged` now and then every `interval`, until the returned task is cancelled.
    @discardableResult
    public func startPolling(every interval: Duration) -> Task<Void, Never> {
        Task { [sleep] in
            while !Task.isCancelled {
                await refreshIfChanged()
                do { try await sleep(interval) } catch { return }
            }
        }
    }

    /// Once the refresh succeeds, `etag` (when not nil) becomes the version later checks compare against.
    private func refresh(thenRemembering etag: String?) -> Task<Void, Never> {
        running?.cancel()
        let count = albumCount()
        refreshesUnderway += 1
        let task = Task { [library, artwork, download, controller] in
            defer { self.refreshesUnderway -= 1 }
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
                if let etag { self.libraryETag = etag }
            } catch {
                guard !Task.isCancelled else { return }
                NSLog("Clutter: couldn't read the Spotify library: %@", String(describing: error))
            }
        }
        running = task
        return task
    }
}
