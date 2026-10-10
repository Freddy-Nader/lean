import AppKit
import WebKit

/// Commands the kernel itself provides. Defaults follow Chrome/Safari.
@MainActor
enum KernelCommands {
    static func register(_ app: App) {
        let c = Commands.shared
        func win(_ f: @escaping (BrowserWindow) -> Void) -> () -> Void {
            { if let w = app.current { f(w) } }
        }
        func web(_ f: @escaping (WKWebView) -> Void) -> () -> Void {
            win { f($0.tab.webView) }
        }

        c.register("window.new", "New Window", keys: ["cmd+n"]) { app.newWindow() }
        c.register("window.close", "Close Window", keys: ["cmd+shift+w"], run: win { $0.close() })

        c.register("address.focus", "Focus Address Bar", keys: ["cmd+l"], run: win { $0.focusAddress() })

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
