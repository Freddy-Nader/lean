import Foundation

/// `lean --check <file.js>`: loads an add-on headlessly (no window) and reports what it registers
/// or why it fails. Exit code 0 = loads cleanly. Used by the /addon skill before handing a file over.
@MainActor
enum Check {
    static func run(_ path: String) -> Int32 {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("✘ no such file: \(url.path)")
            return 1
        }
        let a = JSAddon(file: url, kind: .user)
        a.load()
        // Let promise jobs and short timers from setup run.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        if let e = a.error {
            print("✘ \(a.id): \(e)")
            return 1
        }
        print("✔ \(a.id) — \(a.name)\(a.summary.isEmpty ? "" : ": \(a.summary)")")
        for id in a.commandIDs {
            let c = Commands.shared.all[id]
            print("  command \(id) “\(c?.title ?? id)”" + (Commands.shared.key(for: id).map { " \($0)" } ?? ""))
        }
        if a.pageScript != nil { print("  page script: yes") }
        for line in a.logs { print("  log: \(line)") }
        if !a.id.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }) {
            print("  warning: file name (the add-on id) should be lowercase-with-hyphens")
        }
        for id in a.commandIDs where !id.hasPrefix(a.id.split(separator: "-").first.map(String.init) ?? a.id) {
            print("  warning: command \(id) should start with the add-on id")
        }
        return 0
    }
}
