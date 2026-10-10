import AppKit

/// A native add-on: one Swift file in Sources/LeanKit/Builtin/, listed in `SwiftAddons.all`.
/// Use it only when JavaScript can't do the job (native UI, files, Keychain, SQLite).
/// It gets the same switch, error badge and listing as JS add-ons; changes need `./build.sh`.
@MainActor
public protocol SwiftAddon: AnyObject {
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    /// `.default` = on unless disabled, `.optional` = off unless enabled.
    var kind: JSAddon.Kind { get }
    /// Register commands, slots and hooks. Throwing disables the add-on.
    func load() throws
    /// Undo everything `load` did.
    func unload()
}

@MainActor
public enum SwiftAddons {
    /// Shipped native add-ons, in load order.
    static let all: [SwiftAddon] = [Palette.shared, TabStrip.shared, BrowserImport()]

    static var loaded = Set<String>()
    static var errors: [String: String] = [:]

    static func sync() {
        for a in all {
            let on = AddonHost.shared.isEnabled(a.id, a.kind)
            if on, !loaded.contains(a.id) {
                do { try a.load(); loaded.insert(a.id); errors[a.id] = nil }
                catch { errors[a.id] = "\(error)"; a.unload() }
            } else if !on, loaded.contains(a.id) {
                a.unload()
                loaded.remove(a.id)
                Commands.shared.unregisterAll(owner: a.id)
            }
        }
    }

    static func find(_ id: String) -> SwiftAddon? { all.first { $0.id == id } }
}
