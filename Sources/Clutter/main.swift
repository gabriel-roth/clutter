import AppKit
import ClutterCore
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let artwork = ArtworkStore(directory: LibraryStore.defaultDirectory.appending(path: "Artwork", directoryHint: .isDirectory))
    private let auth = SpotifyAuth()
    private lazy var spotifyLibrary = SpotifyLibrary(accessToken: { [auth] in try await auth.validAccessToken() })
    private lazy var spotifySignIn = SpotifySignIn(auth: auth)
    private var controller: ClutterController?
    /// The standard About panel isn't ours to subclass, so Command-W is handled by a key monitor.
    private var aboutPanel: NSWindow?
    private var closeAboutOnCommandW: Any?
    private var sync: LibrarySync?
    private var statusItem: NSStatusItem?
    private var statusClickMonitor: Any?
    private lazy var settings = SettingsWindowController(
        albumCount: AlbumCount.saved(in: .standard),
        showsInfoOnHover: HoverInfo.isEnabled(in: .standard),
        onAlbumCountChange: { [weak self] count in
            AlbumCount.save(count, in: .standard)
            self?.sync?.refresh()
        },
        onShowsInfoOnHoverChange: { [weak self] showsInfo in
            HoverInfo.save(showsInfo, in: .standard)
            self?.controller?.setShowsInfoOnHover(showsInfo)
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let controller = ClutterController(
            store: LibraryStore(fileURL: LibraryStore.defaultDirectory.appending(path: "library.json")),
            artwork: artwork,
            player: WebAPISpotifyPlayer(library: spotifyLibrary),
            screens: screens.isEmpty ? [CGRect(x: 0, y: 0, width: 1440, height: 900)] : screens,
            coverSize: CoverSize.saved(in: .standard),
            showsInfoOnHover: HoverInfo.isEnabled(in: .standard)
        )
        controller.onRemoveAlbum = { [weak self] album in self?.removeFromLibrary(album) }
        controller.showWindows()
        self.controller = controller
        let sync = LibrarySync(library: spotifyLibrary, artwork: artwork, controller: controller, albumCount: { AlbumCount.saved(in: .standard) })
        self.sync = sync
        Task {
            // The first check comes right away, so it also does the launch refresh.
            if await spotifySignIn.promptIfSignedOut() {
                sync.startPolling(every: .seconds(30))
            }
        }
        controller.onShownByToggle = { NSApp.activate() }
        KeyboardShortcuts.onKeyUp(for: .toggleClutter) { [weak self] in
            self?.controller?.toggle()
        }
        KeyboardShortcuts.onKeyUp(for: .addCurrentAlbum) { [weak self] in
            self?.addCurrentAlbum(nil)
        }
    }

    /// A plain click shows or hides the covers; Command-click or right-click opens `menu`.
    func installStatusItem(menu: NSMenu) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(named: "MenuBarIcon")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "Clutter"
        item.button?.image = icon
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        statusItem = item
        // The system claims Command-clicks on menu bar icons (for rearranging them) and never sends the
        // button's action, but the mouse-down still reaches the app, so catch it here, along with right-clicks.
        statusClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak item] event in
            guard let button = item?.button, event.window === button.window,
                  event.type == .rightMouseDown || event.modifierFlags.contains(.command) else { return event }
            // Attaching the menu just for this click gets the system's own placement under the icon,
            // which a popUp at a guessed point doesn't.
            item?.menu = menu
            button.performClick(nil)
            item?.menu = nil
            return nil
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        controller?.toggle()
    }

    @objc func showAbout(_ sender: Any?) {
        let link = "https://github.com/gabriel-roth/clutter"
        let credits = NSMutableAttributedString(
            string: link,
            attributes: [
                .link: URL(string: link)!,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ]
        )
        credits.addAttribute(.paragraphStyle, value: {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            return style
        }(), range: NSRange(location: 0, length: credits.length))
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
        // AppKit may build a fresh panel after the last one closed, so re-identify it on every open.
        aboutPanel = NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0 is NSPanel } ?? aboutPanel
        if closeAboutOnCommandW == nil {
            closeAboutOnCommandW = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let panel = self?.aboutPanel, panel.isKeyWindow,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                      event.charactersIgnoringModifiers == "w" else { return event }
                panel.performClose(nil)
                return nil
            }
        }
    }

    @objc func tidyCovers(_ sender: Any?) {
        controller?.tidy()
    }

    @objc func scrambleCovers(_ sender: Any?) {
        controller?.scramble()
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

    /// Removes an album whose cover was just closed from the Spotify library, then refreshes so
    /// the next-newest album takes its place. If removing fails, the refresh brings the cover back.
    private func removeFromLibrary(_ album: Album) {
        Task {
            do {
                try await spotifyLibrary.remove(albumURI: album.spotifyURI)
            } catch {
                NSLog("Clutter: couldn't remove %@ from the library: %@", album.title, String(describing: error))
                NSSound.beep()
            }
            controller?.finishRemoving(spotifyURI: album.spotifyURI)
            sync?.refresh()
        }
    }

    /// Saves the playing album to the Spotify library (re-saving it if it's already there, so it
    /// becomes the most recent), then refreshes the desktop and brings its cover to the front.
    @objc func addCurrentAlbum(_ sender: Any?) {
        Task {
            do {
                let albumURI = try await CurrentAlbumFetcher.live.fetchAlbumURI()
                try await spotifyLibrary.bumpToMostRecent(albumURI: albumURI)
                await sync?.refresh().value
                controller?.bringToFront(spotifyURI: albumURI)
            } catch SpotifyLibraryError.removedButNotSaved {
                let alert = NSAlert()
                alert.messageText = "Couldn't save the album again"
                alert.informativeText = "Clutter removed the playing album from your Spotify library to move it to the top, but couldn't save it again. Press Add Currently Playing Album again while it's still playing."
                NSApp.activate()
                alert.runModal()
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
let aboutItem = NSMenuItem(title: "About Clutter", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
aboutItem.target = delegate
appMenu.addItem(aboutItem)
appMenu.addItem(.separator())
let settingsItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
settingsItem.target = delegate
appMenu.addItem(settingsItem)
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Hide Clutter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
hideOthersItem.keyEquivalentModifierMask = [.command, .option]
appMenu.addItem(hideOthersItem)
appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
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

let arrangeCommands = [
    ("Tidy", #selector(AppDelegate.tidyCovers(_:))),
    ("Scramble", #selector(AppDelegate.scrambleCovers(_:))),
]

// Covers are borderless, so keep AppKit from adding "Enter Full Screen" to the View menu.
UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
let viewMenu = NSMenu(title: "View")
for size in CoverSize.allCases {
    let item = NSMenuItem(title: size.title, action: #selector(AppDelegate.setCoverSize(_:)), keyEquivalent: "")
    item.target = delegate
    item.representedObject = size.rawValue
    viewMenu.addItem(item)
}
viewMenu.addItem(.separator())
for (title, action) in arrangeCommands {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = delegate
    viewMenu.addItem(item)
}
let viewMenuItem = NSMenuItem()
viewMenuItem.submenu = viewMenu
mainMenu.addItem(viewMenuItem)

app.mainMenu = mainMenu

// Clutter lives in the menu bar, not the Dock. Clicking the icon shows or hides the covers; Command-click opens this menu.
let statusMenu = NSMenu()
let statusAddItem = NSMenuItem(title: "Add Currently Playing Album", action: #selector(AppDelegate.addCurrentAlbum(_:)), keyEquivalent: "")
statusAddItem.target = delegate
statusAddItem.setShortcut(for: .addCurrentAlbum)
statusMenu.addItem(statusAddItem)
let sizeMenu = NSMenu(title: "Cover Size")
for size in CoverSize.allCases {
    let item = NSMenuItem(title: size.title, action: #selector(AppDelegate.setCoverSize(_:)), keyEquivalent: "")
    item.target = delegate
    item.representedObject = size.rawValue
    sizeMenu.addItem(item)
}
let sizeMenuItem = NSMenuItem(title: "Cover Size", action: nil, keyEquivalent: "")
sizeMenuItem.submenu = sizeMenu
statusMenu.addItem(sizeMenuItem)
for (title, action) in arrangeCommands {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = delegate
    statusMenu.addItem(item)
}
let statusSettingsItem = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
statusSettingsItem.target = delegate
statusMenu.addItem(statusSettingsItem)
statusMenu.addItem(.separator())
let statusAboutItem = NSMenuItem(title: "About Clutter", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
statusAboutItem.target = delegate
statusMenu.addItem(statusAboutItem)
statusMenu.addItem(withTitle: "Quit Clutter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
delegate.installStatusItem(menu: statusMenu)

app.setActivationPolicy(.accessory)
app.run()
