import Foundation
import JavaScriptCore
import WebKit

/// Finds, loads, hot-reloads and isolates add-ons.
///
/// Sources, later ones overriding earlier ones by id (so copying a shipped add-on into the user
/// folder forks it):
///   app bundle  addons/default/*.js    on unless disabled
///   app bundle  addons/optional/*.js   off unless enabled
///   ~/.config/lean/addons/*.js         on unless disabled
@MainActor
public final class AddonHost: NSObject, WKScriptMessageHandler {
    public static let shared = AddonHost()

    public private(set) var addons: [String: JSAddon] = [:]
    public var onChange: (() -> Void)?
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingRescan: DispatchWorkItem?

    static var userDir: URL { Commands.configDir.appending(path: "addons", directoryHint: .isDirectory) }

    // MARK: discovery

    func start() {
        try? FileManager.default.createDirectory(at: Self.userDir, withIntermediateDirectories: true)
        rescan()
        watch()
    }

    private func discover() -> [String: (URL, JSAddon.Kind)] {
        var found: [String: (URL, JSAddon.Kind)] = [:]
        let bundled = Bundle.main.resourceURL?.appending(path: "addons")
        let sources: [(URL?, JSAddon.Kind)] = [
            (bundled?.appending(path: "default"), .default),
            (bundled?.appending(path: "optional"), .optional),
            (Self.userDir, .user),
        ]
        for (dir, kind) in sources {
            guard let dir, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "js" {
                found[f.deletingPathExtension().lastPathComponent] = (f, kind)
            }
        }
        return found
    }

    /// Loads new or changed add-ons, unloads removed or disabled ones. Unchanged ones keep running.
    func rescan() {
        let found = discover()
        for (id, a) in addons {
            let mtime = (try? found[id]?.0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            if found[id] == nil || found[id]!.0 != a.file || mtime != a.modified || !isEnabled(id, a.kind) {
                a.unload()
                addons[id] = nil
            }
        }
        for (id, (file, kind)) in found where addons[id] == nil {
            let a = JSAddon(file: file, kind: kind)
            addons[id] = a
            if isEnabled(id, kind) { a.load() }
        }
        refreshScripts()
        SwiftAddons.sync()
        onChange?()
    }

    private func watch() {
        let fd = open(Self.userDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                // Editors save in bursts (temp file, rename); wait for the burst to finish.
                self?.pendingRescan?.cancel()
                let work = DispatchWorkItem { MainActor.assumeIsolated { self?.rescan() } }
                self?.pendingRescan = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    // MARK: enable / disable / reload

    public func isEnabled(_ id: String, _ kind: JSAddon.Kind) -> Bool {
        kind == .optional ? Settings.shared.strings("addons.enabled").contains(id)
                          : !Settings.shared.strings("addons.disabled").contains(id)
    }

    public func setEnabled(_ id: String, _ on: Bool) {
        guard let kind = addons[id]?.kind ?? SwiftAddons.find(id)?.kind else { return }
        let key = kind == .optional ? "addons.enabled" : "addons.disabled"
        var list = Set(Settings.shared.strings(key))
        if (kind == .optional) == on { list.insert(id) } else { list.remove(id) }
        Settings.shared.set(key, list.sorted())
        reload(id)
    }

    /// Fresh load from disk; also clears a previous error.
    public func reload(_ id: String) {
        addons[id]?.unload()
        addons[id] = nil
        rescan()
    }

    func failed(_ a: JSAddon) {
        refreshScripts()
        App.shared?.current?.toast("Add-on “\(a.id)” stopped: \(a.error?.components(separatedBy: "\n").first ?? "")")
        onChange?()
    }

    // MARK: hooks

    /// Runs a hook across add-ons in id order; the first non-nil result wins.
    @discardableResult
    func emit(_ hook: String, _ payload: [String: Any]) -> [String: Any]? {
        var first: [String: Any]?
        for id in addons.keys.sorted() {
            if let r = addons[id]?.emit(hook, payload) as? [String: Any], first == nil { first = r }
        }
        return first
    }

    // MARK: page scripts

    func attach(_ c: WKUserContentController) {
        controllers.add(c)
        install(into: c)
    }

    private func refreshScripts() { controllers.allObjects.forEach(install) }

    private func install(into c: WKUserContentController) {
        c.removeAllUserScripts()
        for a in addons.values {
            c.removeAllScriptMessageHandlers(from: a.world)
            guard a.isLoaded, let s = a.pageScript else { continue }
            c.addUserScript(s)
            c.add(WeakHandler(self), contentWorld: a.world, name: "lean")
        }
    }

    public func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let a = addons.values.first(where: { $0.world == m.world }), a.isLoaded,
              let body = m.body as? [String: Any], let event = body["e"] as? String else { return }
        if event == "__error" { return a.fail("page: \(body["d"] ?? "")") }
        let tab = m.webView.flatMap { App.shared?.tab(for: $0) }
        _ = a.emit("message", ["tab": Self.describe(tab), "event": event, "data": body["d"] ?? NSNull()])
    }

    // MARK: helpers for the bridge

    static func describe(_ t: Tab?) -> Any {
        guard let t else { return NSNull() }
        return ["id": t.id.uuidString, "url": t.url?.absoluteString ?? "", "title": t.title]
    }

    static func tabAction(_ id: String, _ action: String, _ arg: String) {
        guard let app = App.shared, let t = app.tab(id: id), let w = app.window(containing: t),
              let i = w.tabs.firstIndex(where: { $0 === t }) else { return }
        switch action {
        case "reload": t.webView.reload()
        case "navigate": if let u = Address.resolve(arg) { t.load(u) }
        case "close": w.close(at: i)
        case "focus": w.select(i); w.window?.makeKeyAndOrderFront(nil)
        default: break
        }
    }

    static func fetch(_ url: String, optsJSON: String, callback: JSValue) {
        guard let u = URL(string: url) else { callback.call(withArguments: [0, "", "bad url"]); return }
        var req = URLRequest(url: u)
        let opts = (try? JSONSerialization.jsonObject(with: Data(optsJSON.utf8))) as? [String: Any] ?? [:]
        req.httpMethod = (opts["method"] as? String) ?? "GET"
        (opts["headers"] as? [String: String])?.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let b = opts["body"] as? String { req.httpBody = Data(b.utf8) }
        let cb = UncheckedBox(callback)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let errText = err?.localizedDescription
            DispatchQueue.main.async {
                cb.value.call(withArguments: [status, text, errText ?? NSNull()])
            }
        }.resume()
    }
}

/// WKUserContentController retains message handlers; this breaks the cycle.
@MainActor
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

/// Moves a main-thread-only value through a background callback back to the main thread.
struct UncheckedBox<T>: @unchecked Sendable { let value: T; init(_ v: T) { value = v } }

/// Per add-on JSON storage: ~/.config/lean/addons/<id>.data.json
@MainActor
enum AddonStorage {
    static func file(_ id: String) -> URL { AddonHost.userDir.appending(path: ".\(id).data.json") }

    static func json(_ id: String) -> String {
        (try? String(contentsOf: file(id), encoding: .utf8)) ?? "{}"
    }

    static func set(_ id: String, _ key: String, json value: String) {
        var all = (try? JSONSerialization.jsonObject(with: Data(json(id).utf8))) as? [String: Any] ?? [:]
        all[key] = (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)) ?? NSNull()
        if let d = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: file(id))
        }
    }
}
