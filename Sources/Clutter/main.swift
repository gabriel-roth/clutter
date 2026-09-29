import AppKit
import ClutterCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let artwork = ArtworkStore(directory: LibraryStore.defaultDirectory.appending(path: "Artwork", directoryHint: .isDirectory))
    private var controller: ClutterController?
    private lazy var settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let controller = ClutterController(
            store: LibraryStore(fileURL: LibraryStore.defaultDirectory.appending(path: "library.json")),
            artwork: artwork,
            player: AppleScriptSpotifyPlayer(),
            screens: screens.isEmpty ? [CGRect(x: 0, y: 0, width: 1440, height: 900)] : screens
        )
        controller.showWindows()
        self.controller = controller
        KeyboardShortcuts.onKeyUp(for: .addCurrentAlbum) { [weak self] in
            self?.addCurrentAlbum(nil)
        }
    }

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    @objc func addCurrentAlbum(_ sender: Any?) {
        Task {
            do {
                let (album, artworkData) = try await CurrentAlbumFetcher.live.fetch()
                try artwork.save(artworkData, for: album)
                controller?.add(album)
            } catch {
                NSLog("Clutter: couldn't add the current album: %@", String(describing: error))
                NSSound.beep()
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

let mainMenu = NSMenu()

let appMenu = NSMenu()
let settingsItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
settingsItem.target = delegate
appMenu.addItem(settingsItem)
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Quit Clutter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
let appMenuItem = NSMenuItem()
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

let fileMenu = NSMenu(title: "File")
let addItem = NSMenuItem(title: "Add Currently Playing Album", action: #selector(AppDelegate.addCurrentAlbum(_:)), keyEquivalent: "")
addItem.target = delegate
addItem.setShortcut(for: .addCurrentAlbum)
fileMenu.addItem(addItem)
let fileMenuItem = NSMenuItem()
fileMenuItem.submenu = fileMenu
mainMenu.addItem(fileMenuItem)

app.mainMenu = mainMenu
app.setActivationPolicy(.regular)
app.run()
