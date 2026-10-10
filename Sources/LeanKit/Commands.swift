import AppKit

/// Every action, kernel or add-on, is a named command. Keys map to command ids, never to code.
@MainActor
public final class Commands {
    public static let shared = Commands()

    public struct Command {
        public let id: String
        public let title: String
        public let defaultKeys: [String]
        public let owner: String
        let run: () -> Void
    }

    private(set) var all: [String: Command] = [:]
    private var bindings: [Key: String] = [:]
    private var userOverrides: [String: String?] = [:]
    private var runtime: [String: (id: String?, owner: String)] = [:]
    private var monitor: Any?
    private var watcher: DispatchSourceFileSystemObject?

    public func register(_ id: String, _ title: String, keys: [String] = [], owner: String = "kernel",
                         run: @escaping () -> Void) {
        all[id] = Command(id: id, title: title, defaultKeys: keys, owner: owner, run: run)
        rebuildBindings()
    }

    func unregisterAll(owner: String) {
        all = all.filter { $0.value.owner != owner }
        rebuildBindings()
    }

    public func unregister(_ id: String) {
        all[id] = nil
        rebuildBindings()
    }

    /// Bindings set by add-ons at runtime (`keys.bind`). keys.json still wins.
    func bindRuntime(_ key: String, _ id: String?, owner: String) {
        runtime[key] = (id, owner)
        rebuildBindings()
    }

    func removeRuntimeBindings(owner: String) {
        runtime = runtime.filter { $0.value.owner != owner }
        rebuildBindings()
    }

    @discardableResult
    public func run(_ id: String) -> Bool {
        guard let c = all[id] else { return false }
        c.run()
        return true
    }

    /// The key currently bound to a command, for display in the palette.
    public func key(for id: String) -> String? {
        bindings.first { $0.value == id }?.key.description
    }

    // MARK: key dispatch

    func start() {
        loadUserKeys()
        watchUserKeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let key = Key(event: e), let id = self.bindings[key] else { return e }
            return self.run(id) ? nil : e
        }
    }

    private func rebuildBindings() {
        var b: [Key: String] = [:]
        for c in all.values { for k in c.defaultKeys { if let key = Key(k) { b[key] = c.id } } }
        for (k, r) in runtime {
            guard let key = Key(k) else { continue }
            if let id = r.id { b[key] = id } else { b[key] = nil }
        }
        for (k, id) in userOverrides {
            guard let key = Key(k) else { continue }
            if let id { b[key] = id } else { b[key] = nil }
        }
        bindings = b
    }

    // MARK: ~/.config/lean/keys.json  — {"cmd+k": "palette.open", "cmd+shift+c": null}

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/lean", directoryHint: .isDirectory)
    }
    static var keysFile: URL { configDir.appending(path: "keys.json") }

    private func loadUserKeys() {
        userOverrides = [:]
        if let data = try? Data(contentsOf: Self.keysFile),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj { userOverrides[k] = v as? String }
        }
        rebuildBindings()
    }

    private var stamps: [String: Date] = [:]

    /// The config dir also holds files the app writes often (rank, dev state), so reload only
    /// what actually changed.
    private func configDirChanged() {
        func changed(_ f: URL) -> Bool {
            let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            defer { stamps[f.path] = m }
            return stamps[f.path] != m
        }
        if changed(Self.keysFile) { loadUserKeys() }
        if changed(Settings.file) {
            Settings.shared.reload()
            AddonHost.shared.rescan()
        }
    }

    private func watchUserKeys() {
        try? FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
        let fd = open(Self.configDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.configDirChanged() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }
}

/// A key chord like "cmd+shift+t". Letters are matched by the character the key types with no
/// modifiers on the current layout, so bindings follow the keyboard the user actually has.
struct Key: Hashable, CustomStringConvertible {
    let mods: NSEvent.ModifierFlags.RawValue
    let key: String

    static let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
    static let named: [UInt16: String] = [
        36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape",
        123: "left", 124: "right", 125: "down", 126: "up", 116: "pageup", 121: "pagedown",
    ]

    init?(_ s: String) {
        var m: NSEvent.ModifierFlags = []
        var k: String?
        for part in s.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": m.insert(.command)
            case "shift": m.insert(.shift)
            case "alt", "opt", "option": m.insert(.option)
            case "ctrl", "control": m.insert(.control)
            default: k = part
            }
        }
        guard let k else { return nil }
        mods = m.rawValue
        key = k
    }

    init?(event e: NSEvent) {
        let m = e.modifierFlags.intersection(Self.relevant)
        if let n = Self.named[e.keyCode] {
            key = n
        } else {
            guard let c = e.characters(byApplyingModifiers: []), !c.isEmpty else { return nil }
            key = c.lowercased()
        }
        mods = m.rawValue
    }

    var description: String {
        let m = NSEvent.ModifierFlags(rawValue: mods)
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let glyphs = ["return": "↵", "tab": "⇥", "escape": "⎋", "delete": "⌫", "left": "←", "right": "→", "up": "↑", "down": "↓", "space": "␣"]
        return s + (glyphs[key] ?? key.uppercased())
    }
}
