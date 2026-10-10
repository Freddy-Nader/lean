import AppKit


@MainActor
public final class App: NSObject, NSApplicationDelegate {
    public static func main() {
        let app = NSApplication.shared
        let delegate = App()
        if Dev.sendIfClient() { return }
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private(set) var windows: [BrowserWindow] = []

    /// The window commands act on: the key window, else the last one opened.
    var current: BrowserWindow? {
        windows.first { $0.window?.isKeyWindow == true } ?? windows.last
    }

    public func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.mainMenu = Self.editMenu()
        KernelCommands.register(self)
        Commands.shared.start()
        newWindow(url: CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") && !$0.hasPrefix("/") }))
        NSApp.activate()
        Rules.shared.loadBundled()
        Bench.launched()
        Dev.listen(self)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    @discardableResult
    func newWindow(url: String? = nil) -> BrowserWindow {
        let w = BrowserWindow()
        windows.append(w)
        w.onClose = { [weak self, weak w] in self?.windows.removeAll { $0 === w } }
        w.showWindow(nil)
        if let url { w.load(url) } else { w.focusAddress() }
        return w
    }

    // Text fields need an Edit menu for ⌘C/⌘V/⌘X/⌘A/⌘Z to work. Browser commands are not
    // menu items: they go through the command registry and key map.
    private static func editMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit lean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
