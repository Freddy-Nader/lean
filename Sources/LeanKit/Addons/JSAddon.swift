import AppKit
import JavaScriptCore
import WebKit

/// One JavaScript add-on: a single file, its own JSContext, its own content world for page code.
/// Any error disables it; the browser keeps running.
@MainActor
public final class JSAddon {
    public enum Kind: String { case `default`, optional, user }

    public let id: String
    public let file: URL
    public let kind: Kind
    public private(set) var name = ""
    public private(set) var summary = ""
    public private(set) var error: String?
    public private(set) var commandIDs: [String] = []
    public private(set) var logs: [String] = []
    let modified: Date
    let world: WKContentWorld
    private(set) var pageScript: WKUserScript?
    private var pageDef: (expr: String, regexes: [String], start: Bool)?
    private var pageData = "null"

    private var context: JSContext?
    private var lean: JSValue?

    init(file: URL, kind: Kind) {
        self.file = file
        self.kind = kind
        id = file.deletingPathExtension().lastPathComponent
        world = WKContentWorld.world(name: "addon.\(id)")
        modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    var isLoaded: Bool { context != nil && error == nil }

    // MARK: lifecycle

    func load() {
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return fail("cannot read \(file.path)") }
        let ctx = JSContext()!
        ctx.name = "lean add-on \(id)"
        ctx.exceptionHandler = { [weak self] _, exc in
            let msg = exc.map { "\($0)" + (($0.objectForKeyedSubscript("stack")?.toString()).map { "\n" + $0 } ?? "") } ?? "unknown error"
            MainActor.assumeIsolated { self?.fail(msg) }
        }
        context = ctx
        ctx.evaluateScript(Prelude.host)?.call(withArguments: [makeNative(ctx)])
        lean = ctx.objectForKeyedSubscript("__lean")

        // `export default {…}` → a global, since JSContext has no module loader.
        let body = source.replacingOccurrences(of: #"export\s+default"#, with: "globalThis.__addon =", options: .regularExpression)
        ctx.evaluateScript(body, withSourceURL: file)
        guard error == nil else { return }
        guard let def = ctx.objectForKeyedSubscript("__addon"), def.isObject else {
            return fail("file must `export default { … }`")
        }
        name = def.forProperty("name")?.stringOrNil ?? id
        summary = def.forProperty("description")?.stringOrNil ?? ""

        registerCommands(def)
        ctx.evaluateScript(Self.installHooks)?.call(withArguments: [def, lean!.forProperty("api")!])
        buildPageScript(def)
        if let setup = def.forProperty("setup"), setup.isFunction {
            lean?.invokeMethod("call", withArguments: [setup, lean!.forProperty("api")!])
        }
    }

    func unload() {
        commandIDs.forEach(Commands.shared.unregister)
        commandIDs = []
        Commands.shared.removeRuntimeBindings(owner: id)
        Slots.shared.removeAll(owner: id)
        PaletteGroups.shared.removeAll(owner: id)
        Settings.shared.undeclare(owner: id)
        Rules.shared.removeAll(prefix: "\(id).")
        pageScript = nil
        context?.exceptionHandler = nil
        context = nil
        lean = nil
    }

    func fail(_ message: String) {
        guard error == nil else { return }
        error = message
        log("error: \(message)")
        unload()
        AddonHost.shared.failed(self)
    }

    func log(_ s: String) {
        logs.append(s)
        if logs.count > 50 { logs.removeFirst() }
        FileHandle.standardError.write(Data("[\(id)] \(s)\n".utf8))
    }

    // MARK: calls from the browser

    /// Runs a hook's listeners; returns the first synchronous result, converted to Foundation types.
    func emit(_ hook: String, _ payload: [String: Any]) -> Any? {
        guard isLoaded, let lean, let ctx = context else { return nil }
        let r = lean.invokeMethod("emit", withArguments: [hook, JSValue(object: payload, in: ctx)!])
        guard let r, !r.isUndefined, !r.isNull else { return nil }
        return r.toObject()
    }

    // MARK: setup helpers

    private static let installHooks = """
    (def, api) => {
      const map = { onReady: "ready", onImport: "import", onTabLoad: "tabLoaded", onTabCreated: "tabCreated", onTabClosed: "tabClosed",
                    onMessage: "message", beforeNavigate: "beforeNavigate", beforeDownload: "beforeDownload" };
      for (const k in map) if (typeof def[k] === "function") api.hooks.on(map[k], (p) => def[k](p, api));
    }
    """

    private func registerCommands(_ def: JSValue) {
        guard let cmds = def.forProperty("commands"), cmds.isObject,
              let keys = context?.objectForKeyedSubscript("Object")?.invokeMethod("keys", withArguments: [cmds])?.toArray() as? [String]
        else { return }
        for cid in keys {
            guard let c = cmds.forProperty(cid), let run = c.forProperty("run"), run.isFunction else { continue }
            let title = c.forProperty("title")?.stringOrNil ?? cid
            let key = c.forProperty("key")?.stringOrNil
            Commands.shared.register(cid, title, keys: key.map { [$0] } ?? [], owner: id) { [weak self] in
                guard let self, let lean = self.lean else { return }
                lean.invokeMethod("call", withArguments: [run, lean.forProperty("api")!])
            }
            commandIDs.append(cid)
        }
    }

    private func buildPageScript(_ def: JSValue) {
        guard let page = def.forProperty("page"), page.isObject,
              let run = page.forProperty("run"), run.isFunction,
              let expr = lean?.invokeMethod("asExpression", withArguments: [run])?.toString() else { return }
        let patterns = (page.forProperty("match")?.toArray() as? [String]) ?? ["*://*/*"]
        pageDef = (expr, patterns.map(Self.matchRegex), page.forProperty("runAt")?.stringOrNil == "start")
        rebuildPageScript()
    }

    /// `page.setData(obj)` from the host: baked into the page script as `data` for the next page loads.
    func setPageData(_ json: String) {
        pageData = json
        rebuildPageScript()
        AddonHost.shared.scriptsChanged()
    }

    private func rebuildPageScript() {
        guard let d = pageDef else { return }
        let src = """
        \(Prelude.page)
        window.__leanPage.data = \(pageData);
        if (\(d.regexes.map { "/\($0)/.test(location.href)" }.joined(separator: " || "))) {
          try { (\(d.expr))(window.__leanPage); } catch (e) { window.__leanPage.emit("__error", String(e && e.stack || e)); }
        }
        """
        pageScript = WKUserScript(source: src, injectionTime: d.start ? .atDocumentStart : .atDocumentEnd,
                                  forMainFrameOnly: true, in: world)
    }

    /// Chrome-style match pattern ("*://*.example.com/*") → regex source.
    static func matchRegex(_ p: String) -> String {
        if p == "<all_urls>" { return "^https?:" }
        var out = "^"
        for ch in p {
            switch ch {
            case "*": out += ".*"
            case ".", "/", "?", "+", "(", ")", "[", "]", "{", "}", "|", "^", "$", "\\": out += "\\" + String(ch)
            default: out.append(ch)
            }
        }
        return out + "$"
    }

    // MARK: native bridge

    private func makeNative(_ ctx: JSContext) -> JSValue {
        let n = JSValue(newObjectIn: ctx)!
        let owner = id
        func set(_ name: String, _ block: Any) { n.setObject(block, forKeyedSubscript: name as NSString) }
        // These blocks are created on the main actor and JavaScriptCore calls them on the main thread.
        func main<T>(_ f: () -> T) -> T { f() }

        let fail: @convention(block) (String) -> Void = { [weak self] m in main { self?.fail(m) } }
        let log: @convention(block) (String) -> Void = { [weak self] m in main { self?.log(m) } }
        let activeTab: @convention(block) () -> Any = { main { AddonHost.describe(App.shared?.current?.tab) } }
        let listTabs: @convention(block) () -> Any = { main { (App.shared?.allTabs ?? []).map { AddonHost.describe($0) } } }
        let openTab: @convention(block) (String, Bool) -> Any = { url, bg in
            main {
                guard let u = Address.resolve(url), let w = App.shared?.current else { return NSNull() }
                return AddonHost.describe(w.open(u, background: bg))
            }
        }
        let tabAction: @convention(block) (String, String, String) -> Void = { tid, action, arg in
            main { AddonHost.tabAction(tid, action, arg) }
        }
        let evalInTab: @convention(block) (String, String, JSValue) -> Void = { [weak self] tid, src, cb in
            main {
                guard let self, let t = App.shared?.tab(id: tid) else { cb.call(withArguments: [NSNull(), "no such tab"]); return }
                t.webView.evaluateJavaScript(src, in: nil, in: self.world) { result in
                    MainActor.assumeIsolated {
                        switch result {
                        case .success(let v): cb.call(withArguments: [v, NSNull()])
                        case .failure(let e): cb.call(withArguments: [NSNull(), e.localizedDescription])
                        }
                    }
                }
            }
        }
        let sendToTab: @convention(block) (String, String, String) -> Void = { [weak self] tid, event, json in
            main {
                guard let self, let t = App.shared?.tab(id: tid) else { return }
                let e = (try? String(data: JSONSerialization.data(withJSONObject: [event]), encoding: .utf8)) ?? "[\"\"]"
                t.webView.evaluateJavaScript("window.__lean_dispatch && window.__lean_dispatch(\(e)[0], \(json))",
                                             in: nil, in: self.world) { _ in }
            }
        }
        let bind: @convention(block) (String, JSValue) -> Void = { key, cmd in
            main { Commands.shared.bindRuntime(key, cmd.stringOrNil, owner: owner) }
        }
        let toast: @convention(block) (String) -> Void = { t in main { App.shared?.current?.toast(t) } }
        let storageAll: @convention(block) () -> String = { main { AddonStorage.json(owner) } }
        let storageSet: @convention(block) (String, String) -> Void = { k, v in main { AddonStorage.set(owner, k, json: v) } }
        let setting: @convention(block) (String) -> Any = { k in main { Settings.shared.value(k) ?? NSNull() } }
        let settingDeclare: @convention(block) (String, String, String) -> Void = { key, title, opts in
            main {
                guard Settings.shared.addon(owner, mayDeclare: key) else { return }
                let o = (try? JSONSerialization.jsonObject(with: Data(opts.utf8))) as? [[String]] ?? []
                Settings.shared.declare(key, title, options: o.map { ($0[0], $0[1]) }, owner: owner)
            }
        }
        let settingSet: @convention(block) (String, JSValue) -> Void = { key, v in
            main {
                let value = v.toObject()
                if Settings.shared.addon(owner, maySet: key, value) { Settings.shared.set(key, value) }
            }
        }
        let rulesAdd: @convention(block) (String, String) -> Void = { rid, json in main { Rules.shared.add("\(owner).\(rid)", json: json) } }
        let rulesRemove: @convention(block) (String) -> Void = { rid in main { Rules.shared.remove("\(owner).\(rid)") } }
        let fetch: @convention(block) (String, String, JSValue) -> Void = { url, opts, cb in
            main { AddonHost.fetch(url, optsJSON: opts, callback: cb) }
        }
        let provide: @convention(block) (String, JSValue) -> Void = { name, impl in
            main { Slots.shared.provide(name, impl, owner: owner) }
        }
        let paletteGroup: @convention(block) (String, JSValue) -> Void = { name, provider in
            main { PaletteGroups.shared.add(name, provider, owner: owner) }
        }
        let setTimeout: @convention(block) (JSValue, Double) -> Void = { [weak self] fn, ms in
            DispatchQueue.main.asyncAfter(deadline: .now() + ms / 1000) {
                MainActor.assumeIsolated { if self?.isLoaded == true { fn.call(withArguments: []) } }
            }
        }

        let copy: @convention(block) (String) -> Void = { t in
            main { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
        }
        let openItem: @convention(block) (String, Bool) -> Void = { target, reveal in
            main {
                let u = target.hasPrefix("/") || target.hasPrefix("~")
                    ? URL(fileURLWithPath: (target as NSString).expandingTildeInPath) : URL(string: target)
                guard let u else { return }
                if reveal { NSWorkspace.shared.activateFileViewerSelecting([u]); return }
                // Opening launches apps and scripts, so only web pages and files the user downloaded.
                let downloaded = u.isFileURL && Downloads.shared.items.contains { $0.done && $0.file?.standardizedFileURL == u.standardizedFileURL }
                guard ["http", "https"].contains(u.scheme?.lowercased() ?? "") || downloaded else { return }
                NSWorkspace.shared.open(u)
            }
        }
        let rankMatch: @convention(block) (String, String) -> Any = { q, t in Rank.match(q, t) ?? NSNull() }
        let rankScore: @convention(block) (String, String, String) -> Any = { q, t, k in main { () -> Any in Rank.shared.score(query: q, text: t, key: k).map { $0 as Any } ?? NSNull() } }
        let rankPick: @convention(block) (String) -> Void = { k in main { Rank.shared.pick(k) } }
        let rankForget: @convention(block) (String) -> Void = { k in main { Rank.shared.forget(k) } }
        let downloads: @convention(block) () -> Any = {
            main { Downloads.shared.items.reversed().map { ["url": $0.source?.absoluteString ?? "", "path": $0.file?.path ?? "",
                                                             "done": $0.done, "failed": $0.failed] } }
        }
        let justLaunched: @convention(block) () -> Bool = { main { App.shared?.uptime ?? 0 < 5 } }
        let pageData: @convention(block) (String) -> Void = { [weak self] j in main { self?.setPageData(j) } }
        let rulesBundled: @convention(block) () -> Void = { main { Rules.shared.loadBundled(prefix: "\(owner).") } }

        set("copy", copy); set("openItem", openItem)
        set("rankMatch", rankMatch); set("rankScore", rankScore); set("rankPick", rankPick); set("rankForget", rankForget)
        set("downloads", downloads); set("justLaunched", justLaunched); set("pageData", pageData); set("rulesBundled", rulesBundled)
        set("fail", fail); set("log", log)
        set("activeTab", activeTab); set("listTabs", listTabs); set("openTab", openTab)
        set("tabAction", tabAction); set("evalInTab", evalInTab); set("sendToTab", sendToTab)
        set("bind", bind); set("toast", toast)
        set("storageAll", storageAll); set("storageSet", storageSet); set("setting", setting); set("settingDeclare", settingDeclare); set("settingSet", settingSet)
        set("rulesAdd", rulesAdd); set("rulesRemove", rulesRemove); set("fetch", fetch)
        set("provide", provide); set("paletteGroup", paletteGroup); set("setTimeout", setTimeout)
        return n
    }
}

extension JSValue {
    var stringOrNil: String? { (isUndefined || isNull) ? nil : toString() }
    var isFunction: Bool { isObject && JSObjectIsFunction(context.jsGlobalContextRef, jsValueRef) }
}
