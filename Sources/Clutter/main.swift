import AppKit
import ClutterCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let artwork = ArtworkStore(directory: LibraryStore.defaultDirectory.appending(path: "Artwork", directoryHint: .isDirectory))
    private var controller: ClutterController?
    private lazy var settings = SettingsWindowController()
    private let spotifySignIn = SpotifySignIn(auth: SpotifyAuth())

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let controller = ClutterController(
            store: LibraryStore(fileURL: LibraryStore.defaultDirectory.appending(path: "library.json")),
            artwork: artwork,
            player: AppleScriptSpotifyPlayer(),
            screens: screens.isEmpty ? [CGRect(x: 0, y: 0, width: 1440, height: 900)] : screens,
            coverSize: CoverSize.saved(in: .standard)
        )
        controller.showWindows()
        self.controller = controller
        Task { await spotifySignIn.promptIfSignedOut() }
        KeyboardShortcuts.onKeyUp(for: .addCurrentAlbum) { [weak self] in
            self?.addCurrentAlbum(nil)
        }
    }

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    /// The sender's `representedObject` is the chosen `CoverSize`'s raw value.
    @objc func setCoverSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let size = CoverSize(rawValue: raw) else { return }
        size.save(in: .standard)
        controller?.setCoverSize(size)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setCoverSize(_:)) {
            menuItem.state = menuItem.representedObject as? String == controller?.coverSize.rawValue ? .on : .off
        }
        return true
    }

    @objc func addCurrentAlbum(_ sender: Any?) {
        // Replaced in the LibrarySync task.
        NSSound.beep()
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

// Covers are borderless, so keep AppKit from adding "Enter Full Screen" to the View menu.
UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
let viewMenu = NSMenu(title: "View")
for size in CoverSize.allCases {
    let item = NSMenuItem(title: size.title, action: #selector(AppDelegate.setCoverSize(_:)), keyEquivalent: "")
    item.target = delegate
    item.representedObject = size.rawValue
    viewMenu.addItem(item)
}
let viewMenuItem = NSMenuItem()
viewMenuItem.submenu = viewMenu
mainMenu.addItem(viewMenuItem)

app.mainMenu = mainMenu
app.setActivationPolicy(.regular)
app.run()
