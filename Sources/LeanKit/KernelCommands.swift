import AppKit
import WebKit

/// Commands the kernel itself provides. Defaults follow Chrome/Safari.
@MainActor
enum KernelCommands {
    static func register(_ app: App) {
        let c = Commands.shared
        Settings.shared.declareKernel()
        func win(_ f: @escaping (BrowserWindow) -> Void) -> () -> Void {
            { if let w = app.current { f(w) } }
        }
        func web(_ f: @escaping (WKWebView) -> Void) -> () -> Void {
            win { if let t = $0.tab { f(t.webView) } }
        }

        c.register("window.new", "New Window", keys: ["cmd+n"]) { app.newWindow() }
        c.register("window.close", "Close Window", keys: ["cmd+shift+w"], run: win { $0.close() })

        c.register("tab.new", "New Tab", keys: ["cmd+t"], run: win { w in
            if let p = BrowserWindow.prompt { p(w, "", true) } else { w.add(Tab(), select: true) }
        })
        c.register("tab.close", "Close Tab", keys: ["cmd+w"], run: win { w in
            if w.tabs.isEmpty { w.close() } else { w.close(at: w.activeIndex) }
        })
        c.register("tab.reopen", "Reopen Closed Tab", keys: ["cmd+shift+t"], run: win { w in
            guard let last = Tab.closed.popLast() else { return }
            w.add(Tab(url: last), select: true)
        })
        c.register("tab.next", "Next Tab", keys: ["ctrl+tab", "cmd+shift+]", "cmd+alt+right"], run: win { $0.cycle(1) })
        c.register("tab.previous", "Previous Tab", keys: ["ctrl+shift+tab", "cmd+shift+[", "cmd+alt+left"], run: win { $0.cycle(-1) })
        c.register("tab.moveRight", "Move Tab Right", keys: ["ctrl+shift+pagedown"], run: win { $0.move(by: 1) })
        c.register("tab.moveLeft", "Move Tab Left", keys: ["ctrl+shift+pageup"], run: win { $0.move(by: -1) })
        for n in 1...8 {
            c.register("tab.select\(n)", "Go to Tab \(n)", keys: ["cmd+\(n)"], run: win { $0.select(n - 1) })
        }
        c.register("tab.selectLast", "Go to Last Tab", keys: ["cmd+9"], run: win { $0.select($0.tabs.count - 1) })

        c.register("address.focus", "Edit Address", keys: ["cmd+l"], run: win { $0.focusAddress() })

        c.register("page.reload", "Reload Page", keys: ["cmd+r"], run: web { $0.reload() })
        c.register("page.reloadHard", "Reload Ignoring Cache", keys: ["cmd+shift+r"], run: web { $0.reloadFromOrigin() })
        c.register("page.back", "Back", keys: ["cmd+["], run: web { $0.goBack() })
        c.register("page.forward", "Forward", keys: ["cmd+]"], run: web { $0.goForward() })

        c.register("page.zoomIn", "Zoom In", keys: ["cmd+=", "cmd+shift+="], run: web { $0.pageZoom = min($0.pageZoom + 0.1, 3) })
        c.register("page.zoomOut", "Zoom Out", keys: ["cmd+-"], run: web { $0.pageZoom = max($0.pageZoom - 0.1, 0.3) })
        c.register("page.zoomReset", "Actual Size", keys: ["cmd+0"], run: web { $0.pageZoom = 1 })

        c.register("find.open", "Find in Page", keys: ["cmd+f"], run: win { $0.find.open() })
        c.register("find.next", "Find Next", keys: ["cmd+g"], run: win { $0.find.next(backwards: false) })
        c.register("find.previous", "Find Previous", keys: ["cmd+shift+g"], run: win { $0.find.next(backwards: true) })

        c.register("rules.togglePause", "Pause Blocking on This Site", run: win { w in
            guard let t = w.tab else { return }
            Rules.shared.togglePause(t.url?.host())
            t.webView.reload()
        })

        /// Selects an open lean:// tab (pointing it at `url`), else opens `url` in a new tab.
        func page(_ url: URL) -> () -> Void {
            win { w in
                if let i = w.tabs.firstIndex(where: { $0.url?.scheme == "lean" }) {
                    w.select(i)
                    if w.tabs[i].url != url { w.tabs[i].load(url) }
                } else { w.open(url, background: false) }
            }
        }
        c.register("settings.open", "Settings", keys: ["cmd+,"], run: page(SettingsPage.url))
        c.register("addons.open", "Add-ons", keys: ["cmd+shift+a"], run: page(URL(string: "lean://settings#addons")!))
        c.register("keys.edit", "Edit Keybindings", run: {
            if !FileManager.default.fileExists(atPath: Commands.keysFile.path) { try? "{\n}\n".write(to: Commands.keysFile, atomically: true, encoding: .utf8) }
            NSWorkspace.shared.open(Commands.keysFile)
        })

        c.register("devtools.toggle", "Developer Tools", keys: ["cmd+alt+i"], run: web(Inspector.toggle))
    }
}

/// WebKit has no public call to open Web Inspector; right-click → Inspect Element is the public
/// path. This uses the private `_inspector` object when present and does nothing otherwise.
@MainActor
enum Inspector {
    static func toggle(_ v: WKWebView) {
        guard v.responds(to: NSSelectorFromString("_inspector")),
              let i = v.value(forKey: "_inspector") as? NSObject else { return }
        let visible = (i.value(forKey: "isVisible") as? Bool) ?? false
        let sel = NSSelectorFromString(visible ? "close" : "show")
        if i.responds(to: sel) { i.perform(sel) }
    }
}
