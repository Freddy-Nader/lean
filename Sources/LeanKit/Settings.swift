import Foundation

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

    init() { reload() }

    public func reload() {
        values = (try? Data(contentsOf: Self.file))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    public func string(_ key: String) -> String {
        (values[key] as? String) ?? (Self.defaults[key] as? String) ?? ""
    }

    public func strings(_ key: String) -> [String] { (values[key] as? [String]) ?? [] }

    public func set(_ key: String, _ value: Any?) {
        values[key] = value
        if let d = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: Self.file)
        }
    }

    /// A path setting with ~ expanded.
    public func path(_ key: String) -> URL {
        URL(fileURLWithPath: (string(key) as NSString).expandingTildeInPath, isDirectory: true)
    }
}
