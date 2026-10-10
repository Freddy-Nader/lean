import Foundation
import WebKit

/// lean://settings — declared general settings, then every add-on with its on/off switch, kind,
/// commands, last error and logs, plus which add-on provides each slot. Actions come back through
/// the `leanSettings` handler, accepted only from lean:// pages.
@MainActor
final class SettingsPage: NSObject, WKURLSchemeHandler, WKScriptMessageHandler {
    static let shared = SettingsPage()
    static let url = URL(string: "lean://settings")!

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
              let b = m.body as? [String: Any], let action = b["action"] as? String else { return }
        let s = Settings.shared
        // A page may only touch declared settings and run keys.edit.
        let key = (b["key"] as? String).flatMap { k in s.declared.first { $0.key == k } }
        switch action {
        case "set": if let key, let v = b["value"] as? String { s.set(key.key, v) }
        case "choose": if let key { s.chooseFolder(key.key) }
        case "command": if b["id"] as? String == "keys.edit" { Commands.shared.run("keys.edit") }
        default: break
        }
        guard let id = b["id"] as? String else { return }
        let host = AddonHost.shared
        switch action {
        case "enable": host.setEnabled(id, true)
        case "disable": host.setEnabled(id, false)
        case "reload": host.reload(id)
        case "reveal": if let a = host.addons[id] { NSWorkspace.shared.activateFileViewerSelecting([a.file]) }
        default: break
        }
    }

    /// Re-renders any open settings page.
    func refresh() {
        for t in App.shared?.allTabs ?? [] where t.url?.scheme == "lean" { t.webView.reload() }
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func general() -> String {
        let s = Settings.shared
        let rows = s.declared.map { d -> String in
            let control: String
            if d.options.isEmpty {
                control = "<code>\(esc(s.string(d.key)))</code> <button onclick=\"post({action:'choose',key:'\(esc(d.key))'})\">Choose…</button>"
            } else {
                let cur = s.string(d.key).isEmpty ? (d.options.first?.value ?? "") : s.string(d.key)
                control = "<select onchange=\"post({action:'set',key:'\(esc(d.key))',value:this.value})\">"
                    + d.options.map { "<option value=\"\(esc($0.value))\" \($0.value == cur ? "selected" : "")>\(esc($0.label))</option>" }.joined() + "</select>"
            }
            return "<div class=row><span>\(esc(d.title))</span>\(control)</div>"
        }.joined()
        return rows + "<div class=row><span>Keybindings</span><button onclick=\"post({action:'command',id:'keys.edit'})\">Edit…</button></div>"
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
        <!doctype html><meta charset=utf-8><title>Settings</title>
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
          .row { display: flex; justify-content: space-between; align-items: center; padding: 6px 0; border-bottom: 1px solid color-mix(in srgb, CanvasText 10%, transparent); }
        </style>
        <h1>Settings</h1>
        <h2>General</h2>
        \(general())
        <h2 id=addons>Add-ons</h2>
        <p>Drop a <code>.js</code> file into <code>~/.config/lean/addons/</code>; it loads on save. Copy a shipped add-on there to fork it.</p>
        \(native)\(rows)
        <h2>Slots</h2><table>\(slots)</table>
        <script>const post = (m) => webkit.messageHandlers.leanSettings.postMessage(m);
          const act = (action, id) => post({ action, id });</script>
        """
    }
}
