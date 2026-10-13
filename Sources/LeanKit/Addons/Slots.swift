import Foundation
import JavaScriptCore

/// Replaceable subsystems. One provider per slot; the most recently loaded add-on wins, and the
/// add-ons page shows who provides what. With no provider, the kernel's default behaviour runs.
@MainActor
public final class Slots {
    public static let shared = Slots()
    public static let names = ["downloads", "history", "palette", "tabstrip", "newtab", "suggest", "search", "session"]

    private var providers: [String: [(owner: String, impl: JSValue)]] = [:]
    /// Native providers (Swift add-ons) for UI slots like palette and tabstrip.
    private var native: [String: String] = [:]

    func provideNative(_ name: String, owner: String) { native[name] = owner }
    func removeNative(_ name: String, owner: String) { if native[name] == owner { native[name] = nil } }

    func provide(_ name: String, _ impl: JSValue, owner: String) {
        providers[name, default: []].removeAll { $0.owner == owner }
        providers[name, default: []].append((owner, impl))
    }

    func removeAll(owner: String) {
        for k in providers.keys { providers[k]?.removeAll { $0.owner == owner } }
    }

    public func owner(of name: String) -> String? { providers[name]?.last?.owner ?? native[name] }

    /// Calls `method` on the slot's provider; nil when nobody provides it or the call fails.
    func call(_ name: String, _ method: String, _ args: [Any]) -> Any? {
        guard let impl = providers[name]?.last?.impl, let f = impl.forProperty(method), f.isFunction,
              let r = f.call(withArguments: args), !r.isUndefined, !r.isNull else { return nil }
        return r.toObject()
    }
}

/// Groups add-ons contribute to the palette. Each provider maps a query to rows.
@MainActor
public final class PaletteGroups {
    public static let shared = PaletteGroups()
    public struct Row { public let title: String; public let subtitle: String; public let url: URL?; public let run: () -> Void }

    private var groups: [(name: String, owner: String, provider: JSValue)] = []

    func add(_ name: String, _ provider: JSValue, owner: String) { groups.append((name, owner, provider)) }
    func removeAll(owner: String) { groups.removeAll { $0.owner == owner } }

    public func query(_ q: String) -> [(group: String, rows: [Row])] {
        groups.compactMap { g in
            guard let arr = g.provider.call(withArguments: [q]), arr.isArray, let n = arr.forProperty("length")?.toInt32() else { return nil }
            let rows: [Row] = (0..<n).compactMap { i -> Row? in
                guard let item = arr.atIndex(Int(i)), let title = item.forProperty("title")?.stringOrNil else { return nil }
                let run = item.forProperty("run")
                return Row(title: title, subtitle: item.forProperty("subtitle")?.stringOrNil ?? "",
                           url: item.forProperty("url")?.stringOrNil.flatMap(URL.init(string:))) {
                    if let run, run.isFunction { run.call(withArguments: []) }
                }
            }
            return rows.isEmpty ? nil : (g.name, rows)
        }
    }
}
