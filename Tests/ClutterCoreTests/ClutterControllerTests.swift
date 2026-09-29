import AppKit
import Testing
@testable import ClutterCore

@MainActor
private final class SpyPlayer: SpotifyPlayer {
    var played: [Album] = []
    func play(_ album: Album) { played.append(album) }
}

private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

@MainActor @Test func makesOneWindowPerAlbumAtTheLaidOutFrames() {
    let controller = ClutterController(albums: Album.all, player: SpyPlayer(), visibleFrame: screen) { _ in nil }
    #expect(controller.windows.map(\.album) == Album.all)
    #expect(controller.windows.map(\.frame)
        == WindowLayout.frames(count: 6, size: ClutterController.windowSize, in: screen))
}

@MainActor @Test func doubleClickingAWindowPlaysItsAlbum() {
    let player = SpyPlayer()
    let controller = ClutterController(albums: Album.all, player: player, visibleFrame: screen) { _ in nil }
    controller.windows[3].albumView.onDoubleClick?()
    #expect(player.played == [Album.all[3]])
}

@MainActor @Test func passesEachAlbumsImageToItsWindow() {
    let images = Dictionary(uniqueKeysWithValues: Album.all.map { ($0.artworkName, NSImage(size: CGSize(width: 1, height: 1))) })
    let controller = ClutterController(albums: Album.all, player: SpyPlayer(), visibleFrame: screen) { images[$0.artworkName] }
    for window in controller.windows {
        #expect(window.albumView.image === images[window.album.artworkName])
    }
}
