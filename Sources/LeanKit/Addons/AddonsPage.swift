import Foundation
import WebKit

/// lean://addons — every add-on with its on/off switch, kind, commands, last error and logs,
/// plus which add-on provides each slot. Actions come back through the `leanAddons` handler,
/// accepted only from lean:// pages.
@MainActor
final class AddonsPage: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
    static let shared = AddonsPage()
    static let url = URL(string: "lean://addons")!

    func webView(_ v: WKWebView, start task: WKURLSchemeTask) {
        let html = Data(render().utf8)
        task.didReceive(URLResponse(url: task.request.url ?? Self.url, mimeType: "text/html",
                                    expectedContentLength: html.count, textEncodingName: "utf-8"))
        task.didReceive(html)
        task.didFinish()
    }

    func webView(_ v: WKWebView, stop task: WKURLSchemeTask) {}

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard m.frameInfo.request.url?.scheme == "lean",
              let b = m.body as? [String: Any], let action = b["action"] as? String, let id = b["id"] as? String else { return }
        let host = AddonHost.shared
        switch action {
        case "enable": host.setEnabled(id, true)
        case "disable": host.setEnabled(id, false)
        case "reload": host.reload(id)
        case "reveal": if let a = host.addons[id] { NSWorkspace.shared.activateFileViewerSelecting([a.file]) }
        default: break
        }
    }

    /// Re-renders any open add-ons page.
    func refresh() {
        for t in App.shared?.allTabs ?? [] where t.url?.scheme == "lean" { t.webView.reload() }
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func render() -> String {
        let host = AddonHost.shared
        let rows = host.addons.values.sorted { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }.map { a -> String in
            let on = host.isEnabled(a.id, a.kind)
            let cmds = a.commandIDs.map { id in
                "<code>\(esc(id))</code>" + (Commands.shared.key(for: id).map { " <kbd>\(esc($0))</kbd>" } ?? "")
            }.joined(separator: " ")
            let err = a.error.map { "<pre class=err>\(esc($0))</pre>" } ?? ""
            let logs = a.logs.isEmpty ? "" : "<details><summary>log</summary><pre>\(esc(a.logs.suffix(20).joined(separator: "\n")))</pre></details>"
            return """
            <section class="\(on ? "" : "off")">
              <header>
                <label><input type=checkbox \(on ? "checked" : "") onchange="act(this.checked?'enable':'disable','\(a.id)')">
                <b>\(esc(a.name.isEmpty ? a.id : a.name))</b></label>
                <span class=kind>\(a.kind.rawValue)</span>
                <span class=spacer></span>
                <button onclick="act('reload','\(a.id)')">Reload</button>
                <button onclick="act('reveal','\(a.id)')">Show file</button>
              </header>
              <p>\(esc(a.summary))</p>
              \(cmds.isEmpty ? "" : "<p class=cmds>\(cmds)</p>")
              \(err)\(logs)
            </section>
            """
        }.joined()
        let native = SwiftAddons.all.map { a -> String in
            let on = host.isEnabled(a.id, a.kind)
            let cmds = Commands.shared.all.values.filter { $0.owner == a.id }.map(\.id).sorted().map { id in
                "<code>\(esc(id))</code>" + (Commands.shared.key(for: id).map { " <kbd>\(esc($0))</kbd>" } ?? "")
            }.joined(separator: " ")
            let err = SwiftAddons.errors[a.id].map { "<pre class=err>\(esc($0))</pre>" } ?? ""
            return """
            <section class="\(on ? "" : "off")">
              <header>
                <label><input type=checkbox \(on ? "checked" : "") onchange="act(this.checked?'enable':'disable','\(a.id)')">
                <b>\(esc(a.name))</b></label>
                <span class=kind>\(a.kind.rawValue) · swift</span>
              </header>
              <p>\(esc(a.summary))</p>
              \(cmds.isEmpty ? "" : "<p class=cmds>\(cmds)</p>")\(err)
            </section>
            """
        }.joined()
        let slots = Slots.names.map { "<tr><td><code>\($0)</code></td><td>\(esc(Slots.shared.owner(of: $0) ?? "kernel default"))</td></tr>" }.joined()
        return """
        <!doctype html><meta charset=utf-8><title>Add-ons</title>
        <style>
          :root { color-scheme: light dark; font: 13px -apple-system, system-ui; }
          body { max-width: 760px; margin: 32px auto; padding: 0 16px; }
          h1 { font-size: 20px; } h2 { font-size: 14px; margin-top: 28px; color: GrayText; }
          section { border: 1px solid color-mix(in srgb, CanvasText 15%, transparent); border-radius: 8px; padding: 10px 14px; margin: 10px 0; }
          section.off { opacity: .55; }
          header { display: flex; gap: 8px; align-items: center; } .spacer { flex: 1; }
          .kind { font-size: 11px; color: GrayText; border: 1px solid; border-radius: 4px; padding: 0 5px; }
          p { margin: 6px 0; } .cmds code { margin-right: 4px; }
          kbd { font: 11px ui-monospace; padding: 0 4px; border-radius: 3px; background: color-mix(in srgb, CanvasText 10%, transparent); }
          pre { white-space: pre-wrap; font: 11px ui-monospace; } .err { color: #d33; }
          td { padding: 2px 12px 2px 0; }
        </style>
        <h1>Add-ons</h1>
        <p>Drop a <code>.js</code> file into <code>~/.config/lean/addons/</code>; it loads on save. Copy a shipped add-on there to fork it.</p>
        \(native)\(rows)
        <h2>Slots</h2><table>\(slots)</table>
        <script>const act = (action, id) => webkit.messageHandlers.leanAddons.postMessage({ action, id });</script>
        """
    }
}
