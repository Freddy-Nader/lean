import CryptoKit
import Foundation
import WebKit

/// Rule-list engine. Compiles WebKit content-blocker JSON once (cached by content hash in
/// WebKit's store) and applies it to every tab. Lists come from the app bundle's rules folder and,
/// later, from add-ons via `add`. Blocking happens inside WebKit before requests start.
@MainActor
public final class Rules {
    public static let shared = Rules()

    public private(set) var active: [String: Int] = [:]   // list id → JSON size in bytes
    public private(set) var errors: [String: String] = [:]
    private var lists: [String: WKContentRuleList] = [:]
    private let store = WKContentRuleListStore.default()!
    /// Each tab has its own controller, so pausing a site only strips rules from tabs showing it.
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private var stripped = Set<ObjectIdentifier>()

    /// Loads every *.json in the bundle's rules folder. Cached lists apply in milliseconds;
    /// first-time compiles run in WebKit's background process without blocking launch.
    func loadBundled(prefix: String = "") {
        guard let dir = Bundle.main.resourceURL?.appending(path: "rules"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return }
        for f in files where f.pathExtension == "json" {
            // Cache key from size + mtime, so a cached list never needs its JSON read at launch.
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let stamp = "\(v?.fileSize ?? 0)-\(Int(v?.contentModificationDate?.timeIntervalSince1970 ?? 0))"
            add(prefix + f.deletingPathExtension().lastPathComponent, key: stamp, size: v?.fileSize ?? 0) {
                (try? String(contentsOf: f, encoding: .utf8)) ?? "[]"
            }
        }
    }

    /// Add-on entry point: rules given as JSON text.
    public func add(_ id: String, json: String) {
        let hash = SHA256.hash(data: Data(json.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        add(id, key: hash, size: json.utf8.count) { json }
    }

    private func add(_ id: String, key: String, size: Int, json: @escaping () -> String) {
        let ident = "\(id)-\(key)"
        store.lookUpContentRuleList(forIdentifier: ident) { [weak self] cached, _ in
            MainActor.assumeIsolated {
                if let cached { self?.install(id, cached, count: size); return }
                self?.store.compileContentRuleList(forIdentifier: ident, encodedContentRuleList: json()) { list, error in
                    MainActor.assumeIsolated {
                        if let list { self?.install(id, list, count: size) }
                        if let error { self?.errors[id] = error.localizedDescription }
                    }
                }
            }
        }
    }

    public func remove(_ id: String) {
        guard let old = lists.removeValue(forKey: id) else { return }
        for c in controllers.allObjects { c.remove(old) }
        active[id] = nil
    }

    public func removeAll(prefix: String) {
        for id in lists.keys where id.hasPrefix(prefix) { remove(id) }
    }

    private func install(_ id: String, _ list: WKContentRuleList, count: Int) {
        remove(id)
        lists[id] = list
        active[id] = count
        for c in controllers.allObjects where !stripped.contains(ObjectIdentifier(c)) { c.add(list) }
    }

    /// Called for each new tab.
    func attach(_ c: WKUserContentController) {
        controllers.add(c)
        lists.values.forEach(c.add)
    }

    /// Called before each main-frame navigation: strips or restores rules for that tab.
    func sync(_ c: WKUserContentController, topHost: String?) {
        let id = ObjectIdentifier(c)
        let pause = isPaused(topHost)
        guard pause != stripped.contains(id) else { return }
        if pause { stripped.insert(id); c.removeAllContentRuleLists() }
        else { stripped.remove(id); lists.values.forEach(c.add) }
    }

    // MARK: per-site pause

    public func isPaused(_ host: String?) -> Bool {
        guard let host else { return false }
        return pausedHosts.contains(Self.site(host))
    }

    public func togglePause(_ host: String?) {
        guard let host else { return }
        var set = pausedHosts
        let s = Self.site(host)
        if set.contains(s) { set.remove(s) } else { set.insert(s) }
        Settings.shared.set("rules.paused", set.sorted())
    }

    private var pausedHosts: Set<String> { Set(Settings.shared.strings("rules.paused")) }

    /// "www.news.example.com" → "news.example.com" (drops www only; good enough for pausing).
    static func site(_ host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
}
