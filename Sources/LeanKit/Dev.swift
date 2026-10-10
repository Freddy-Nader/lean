import AppKit

/// Development channel, on only when launched with LEAN_DEV=1.
/// `lean --run <command-id> [arg]` from another shell runs a command in the running app and the app
/// writes its state to ~/.config/lean/dev-state.json, so tests can drive and inspect it.
@MainActor
enum Dev {
    nonisolated static let name = Notification.Name("app.lean.browser.run")
    static var stateFile: URL { Commands.configDir.appending(path: "dev-state.json") }

    /// Returns true if this process was a `--run` client and should exit.
    nonisolated static func sendIfClient() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--run"), i + 1 < args.count else { return false }
        let payload = args[(i + 1)...].joined(separator: "\u{1f}")
        DistributedNotificationCenter.default().postNotificationName(name, object: payload, deliverImmediately: true)
        return true
    }

    static func listen(_ app: App) {
        guard ProcessInfo.processInfo.environment["LEAN_DEV"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { n in
            let parts = (n.object as? String)?.components(separatedBy: "\u{1f}") ?? []
            MainActor.assumeIsolated {
                guard let id = parts.first else { return }
                if id == "load", parts.count > 1 { app.current?.load(parts[1]) } else { Commands.shared.run(id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { dump(app) } }
            }
        }
        dump(app)
    }

    static func dump(_ app: App) {
        let windows = app.windows.map { w in
            [
                "key": w === app.current,
                "active": w.activeIndex,
                "tabs": w.tabs.map { ["title": $0.title, "url": $0.url?.absoluteString ?? ""] },
            ] as [String: Any]
        }
        let keys = Dictionary(uniqueKeysWithValues: Commands.shared.all.keys.map { ($0, Commands.shared.key(for: $0) ?? "") })
        let downloads = Downloads.shared.items.map { ["file": $0.file?.path ?? "", "done": $0.done, "failed": $0.failed] as [String: Any] }
        let state: [String: Any] = ["windows": windows, "commands": keys, "downloads": downloads]
        if let d = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: stateFile)
        }
    }
}
