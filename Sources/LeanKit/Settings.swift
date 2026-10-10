import AppKit

/// Kernel settings in ~/.config/lean/settings.json. Add-ons read and write through here too.
@MainActor
public final class Settings {
    public static let shared = Settings()
    static var file: URL { Commands.configDir.appending(path: "settings.json") }

    private var values: [String: Any] = [:]
    public static let defaults: [String: Any] = [
        "downloads.folder": "~/Downloads",
        "search.template": "https://www.google.com/search?q=%s",
    ]

    /// A user-facing setting. Declaring it is what puts it on lean://settings and in the palette.
    public struct Declared {
        public let key: String, title: String, icon: String
        /// (label, value) choices; empty = a folder picked with an open panel.
        public let options: [(label: String, value: String)]
        let owner: String
    }
    public static let changed = Notification.Name("lean.settingsChanged")   // object: key, or nil after reload
    private(set) var declared: [Declared] = []

    init() { reload() }

    public func reload() {
        values = (try? Data(contentsOf: Self.file))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// Re-declaring a key replaces it.
    func declare(_ key: String, _ title: String, icon: String = "gearshape", options: [(String, String)] = [], owner: String = "kernel") {
        declared.removeAll { $0.key == key }
        declared.append(Declared(key: key, title: title, icon: icon, options: options.map { (label: $0.0, value: $0.1) }, owner: owner))
    }

    func undeclare(owner: String) { declared.removeAll { $0.owner == owner } }

    func declareKernel() {
        declare("downloads.folder", "Downloads Folder", icon: "arrow.down.circle")
        declare("search.template", "Search Engine", icon: "magnifyingglass", options: [
            ("Google", "https://www.google.com/search?q=%s"), ("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
            ("Kagi", "https://kagi.com/search?q=%s"), ("Perplexity", "https://www.perplexity.ai/search?q=%s"),
            ("Bing", "https://www.bing.com/search?q=%s")])
    }

    /// Open panel for a folder setting.
    func chooseFolder(_ key: String) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.directoryURL = path(key)
        if p.runModal() == .OK, let u = p.url { set(key, (u.path as NSString).abbreviatingWithTildeInPath) }
    }

    public func string(_ key: String) -> String {
        (values[key] as? String) ?? (Self.defaults[key] as? String) ?? ""
    }

    public func value(_ key: String) -> Any? { values[key] ?? Self.defaults[key] }

    public func strings(_ key: String) -> [String] { (values[key] as? [String]) ?? [] }

    public func set(_ key: String, _ value: Any?) {
        values[key] = value
        if let d = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: Self.file)
        }
        NotificationCenter.default.post(name: Self.changed, object: key)
    }

    /// A path setting with ~ expanded.
    public func path(_ key: String) -> URL {
        URL(fileURLWithPath: (string(key) as NSString).expandingTildeInPath, isDirectory: true)
    }
}
