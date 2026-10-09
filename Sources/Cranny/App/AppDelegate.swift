import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screenSignature = ""
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenu.install()
        NotchNookImporter.importIfNeeded()
        NowPlaying.shared.start()
        LiveActivityCenter.shared.start()
        CommandCenter.shared.start()
        rebuildControllers()
        MouseTracker.shared.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.rebuildControllers() }
        }
        AppSettings.shared.$enableOnNonNotchScreens
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildControllers(force: true) }
            .store(in: &bag)

        if !AppSettings.shared.hasCompletedOnboarding {
            WelcomeWindowController.shared.show()
        }
        // Warm up things the tray needs, so the first open doesn't hitch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            _ = AirDrop.icon
            _ = TrayItemView.placeholder
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NowPlaying.shared.stop()
        CameraService.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(CommandCenter.shared.handle)
    }

    func rebuildControllers(force: Bool = false) {
        let showEverywhere = AppSettings.shared.enableOnNonNotchScreens
        let screens = NSScreen.screens.filter { $0.hasNotch || showEverywhere }
        let signature = screens.map { "\($0.displayID):\($0.frame):\($0.hasNotch)" }.joined(separator: "|")
        guard force || signature != screenSignature else { return }
        screenSignature = signature
        NotchRegistry.controllers.forEach { $0.tearDown() }
        NotchRegistry.controllers = screens.map { NotchController(screen: $0) }
        Log.app.info("Notch windows on \(screens.count) screen(s)")
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        SettingsWindowController.shared.show(pane: .about)
    }
}

@MainActor
enum AppMenu {
    static func install() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Cranny", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Cranny", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}

/// Handles cranny:// URLs and distributed-notification commands, so the notch
/// can be driven from Shortcuts, Raycast, scripts, etc.
@MainActor
final class CommandCenter {
    static let shared = CommandCenter()
    static let notificationName = Notification.Name("io.github.rdbms234.Cranny.command")

    private init() {}

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { CommandCenter.shared.run(command) }
        }
    }

    func handle(_ url: URL) {
        Log.app.notice("URL: \(url.absoluteString, privacy: .public)")
        guard url.scheme?.lowercased() == "cranny" else { return }
        var words = [url.host ?? ""]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for key in ["tab", "pane"] {
            if let value = query.first(where: { $0.name == key })?.value { words.append(value) }
        }
        run(words.joined(separator: " "))
    }

    func run(_ command: String) {
        Log.app.notice("Command: \(command, privacy: .public)")
        let words = command.split(separator: " ").map(String.init)
        guard let verb = words.first?.lowercased() else { return }
        let argument = words.count > 1 ? words[1] : nil
        let controller = NotchRegistry.primary
        switch verb {
        case "open":
            controller?.open(tab: argument.flatMap(NotchTab.init(rawValue:)) ?? .nook, pinned: true)
        case "close":
            NotchRegistry.controllers.forEach { $0.close() }
        case "toggle":
            controller?.toggle()
        case "settings":
            SettingsWindowController.shared.show(pane: argument.flatMap(SettingsWindowController.Pane.init(name:)))
        case "hover":
            if let controller {
                let rect = controller.notchRect()
                MouseTracker.shared.simulate(NSPoint(x: rect.midX, y: rect.maxY - 2), for: Double(argument ?? "") ?? 3)
            }
        case "media":
            switch argument {
            case "toggle": NowPlaying.shared.togglePlayPause()
            case "next": NowPlaying.shared.next()
            case "previous": NowPlaying.shared.previous()
            default: break
            }
        default:
            Log.app.info("Unknown command: \(command)")
        }
    }
}
