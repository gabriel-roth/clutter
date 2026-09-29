import AppKit
import ClutterCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ClutterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let controller = ClutterController(albums: Album.all, player: AppleScriptSpotifyPlayer(), visibleFrame: visibleFrame) { album in
            Bundle.main.image(forResource: album.artworkName)
        }
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
