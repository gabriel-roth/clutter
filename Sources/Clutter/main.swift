import AppKit
import ClutterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ClutterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let support = LibraryStore.defaultDirectory
        let screens = NSScreen.screens.map(\.visibleFrame)
        let controller = ClutterController(
            store: LibraryStore(fileURL: support.appending(path: "library.json")),
            artwork: ArtworkStore(directory: support.appending(path: "Artwork", directoryHint: .isDirectory)),
            player: AppleScriptSpotifyPlayer(),
            screens: screens.isEmpty ? [CGRect(x: 0, y: 0, width: 1440, height: 900)] : screens
        )
        controller.showWindows()
        self.controller = controller
    }
}

let app = NSApplication.shared
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit Clutter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
app.mainMenu = mainMenu

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
