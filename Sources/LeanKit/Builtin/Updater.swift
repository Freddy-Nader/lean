import AppKit
import CryptoKit

/// What CI publishes with every build of main: the commit, the SHA-256 of the lean binary, and the
/// SHA-256 of every add-on file (path under Resources → hash).
struct UpdateManifest: Codable, Equatable {
    let commit: String
    let binary: String
    let files: [String: String]
}

/// Auto-update from GitHub (default Swift add-on). CI builds each push to main and publishes the
/// rolling release `latest`: manifest.json, the binary, and the add-on files (scripts/manifest.py).
/// A check downloads only what differs from what is installed:
///   - add-on files land in ~/.config/lean/updates/ (layered over the signed bundle by AddonHost)
///     and hot-reload, no restart;
///   - a changed binary replaces Contents/MacOS/lean, the app is re-signed ad hoc, and the new
///     build runs at the next launch ("Restart to Finish Update" does it now). The old binary is
///     kept at ~/.config/lean/updates/lean.prev.
/// Everything is verified against the manifest's hashes before anything on disk changes.
/// Local builds (./build.sh without LEAN_COMMIT) never update themselves.
@MainActor
final class Updater: SwiftAddon {
    let id = "updater", name = "Auto-update", kind = JSAddon.Kind.default
    let summary = "Keeps lean current with GitHub. Changed add-ons apply live; a new build applies on restart."

    static let defaultBase = "https://github.com/Freddy-Nader/lean/releases/download/latest"
    static let interval: Duration = .seconds(6 * 3600)

    /// The commit this app was built from; "dev" for local builds.
    static var bundleCommit: String { (Bundle.main.object(forInfoDictionaryKey: "LeanCommit") as? String) ?? "dev" }
    /// `LEAN_UPDATE_URL` points the updater at another folder with the same layout (testing).
    static var base: String { ProcessInfo.processInfo.environment["LEAN_UPDATE_URL"] ?? defaultBase }
    static var dir: URL { Commands.configDir.appending(path: "updates", directoryHint: .isDirectory) }

    private var loop: Task<Void, Never>?
    private var busy = false

    func load() throws {
        Commands.shared.register("update.check", "Check for Updates", owner: id) { [weak self] in
            guard let self else { return }
            Task { await self.check(manual: true) }
        }
        guard Self.bundleCommit != "dev" else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self?.check(manual: false)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func unload() {
        loop?.cancel()
        loop = nil
    }

    // MARK: pure parts

    struct State: Codable, Equatable {
        /// The `LeanCommit` of the app these files were layered over; a reinstall invalidates them.
        var base: String
        var commit: String
        /// Manifest hash of the binary last installed, and the hash that binary has on disk after
        /// re-signing (signing changes the bytes, so the two differ). Trusted only while the file
        /// on disk still has that hash.
        var binary: String?
        var exe: String?
    }

    static func readState(in dir: URL = dir) -> State? {
        (try? Data(contentsOf: dir.appending(path: "state.json"))).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
    }

    /// The folder of updated add-ons (`<it>/addons/default|optional`), or nil when there is none or it
    /// belongs to a different install or a dev build.
    static func overlay(in dir: URL = dir, commit: String = bundleCommit) -> URL? {
        commit != "dev" && readState(in: dir)?.base == commit ? dir : nil
    }

    /// Paths from the manifest the app may write: only add-on scripts, never anything that escapes.
    static func isSafe(_ path: String) -> Bool {
        path.range(of: #"^addons/(default|optional)/[A-Za-z0-9_-]+\.js\z"#, options: .regularExpression) != nil
    }

    /// Release asset name of a path: addons/default/x.js → addons__default__x.js
    static func asset(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "__") }

    /// Manifest files whose installed content differs (or is missing).
    static func stale(_ m: UpdateManifest, local: (String) -> String?) -> [String] {
        m.files.filter { local($0.key) != $0.value }.keys.sorted()
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hash of the add-on file in effect: the update if there is one, else the app's own.
    static func installedHash(_ path: String) -> String? {
        let urls = [overlay()?.appending(path: path), Bundle.main.resourceURL?.appending(path: path)]
        return urls.lazy.compactMap { $0 }.compactMap { try? Data(contentsOf: $0) }.first.map(sha256)
    }

    // MARK: check

    enum Failure: LocalizedError {
        case http(String), hash(String), unsafe(String), notWritable, sign(String)
        var errorDescription: String? {
            switch self {
            case .http(let a): "could not download \(a)"
            case .hash(let a): "\(a) does not match its manifest hash"
            case .unsafe(let p): "manifest lists a path I will not write: \(p)"
            case .notWritable: "lean.app is in a read-only folder"
            case .sign(let o): "re-signing failed: \(o)"
            }
        }
    }

    func check(manual: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard Self.bundleCommit != "dev" else {
            if manual { toast("This is a local build; it does not update itself.") }
            return
        }
        do {
            let m = try JSONDecoder().decode(UpdateManifest.self, from: try await fetch("manifest.json"))
            if let bad = m.files.keys.first(where: { !Self.isSafe($0) }) { throw Failure.unsafe(bad) }
            guard let exe = Bundle.main.executableURL else { return }
            let onDisk = Self.sha256(try Data(contentsOf: exe))
            var have = onDisk
            if let s = Self.readState(), s.base == Self.bundleCommit, s.exe == onDisk, let b = s.binary { have = b }
            let newBinary = have != m.binary
            let files = Self.stale(m, local: Self.installedHash)
            if files.isEmpty, !newBinary {
                if manual { toast("lean is up to date.") }
                return
            }
            // Download and verify everything first, so a failure changes nothing.
            var contents: [String: Data] = [:]
            for p in files { contents[p] = try await fetch(Self.asset(p), sha256: m.files[p]) }
            let binary = newBinary ? try await fetch("lean", sha256: m.binary) : nil

            if let binary { try install(binary: binary, at: exe) }
            try write(contents, State(base: Self.bundleCommit, commit: m.commit, binary: newBinary ? m.binary : have,
                                      exe: newBinary ? Self.sha256(try Data(contentsOf: exe)) : onDisk))
            AddonHost.shared.rescan()

            let names = files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            if binary != nil {
                registerRestart()
                toast("Update ready. Restart from the palette to finish." + (names.isEmpty ? "" : " Add-ons updated: \(names)."))
            } else {
                toast("Updated add-ons: \(names)")
            }
        } catch {
            if manual { toast("Update failed: \(error.localizedDescription)") }
        }
    }

    private func fetch(_ asset: String, sha256 expected: String? = nil) async throws -> Data {
        guard let url = URL(string: "\(Self.base)/\(asset)") else { throw Failure.http(asset) }
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.http(asset) }
        if let expected, Self.sha256(data) != expected { throw Failure.hash(asset) }
        return data
    }

    // MARK: apply

    private func write(_ files: [String: Data], _ state: State) throws {
        let fm = FileManager.default
        if Self.readState()?.base != Self.bundleCommit {   // leftovers from another install
            try? fm.removeItem(at: Self.dir.appending(path: "addons"))
        }
        for (path, data) in files {
            let dest = Self.dir.appending(path: path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
        }
        try fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: Self.dir.appending(path: "state.json"), options: .atomic)
    }

    /// Renames the new binary over the old one (atomic; the running process keeps its own copy),
    /// then re-signs the bundle. A failed signature puts the old binary back.
    private func install(binary: Data, at exe: URL) throws {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: exe.deletingLastPathComponent().path) else { throw Failure.notWritable }
        let prev = Self.dir.appending(path: "lean.prev")
        try fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? fm.removeItem(at: prev)
        try fm.copyItem(at: exe, to: prev)
        try Self.swap(binary, into: exe)
        let (status, output) = Self.run("/usr/bin/codesign", ["--force", "--sign", "-", Bundle.main.bundleURL.path])
        if status != 0 {
            if let old = try? Data(contentsOf: prev) {
                try? Self.swap(old, into: exe)
                _ = Self.run("/usr/bin/codesign", ["--force", "--sign", "-", Bundle.main.bundleURL.path])
            }
            throw Failure.sign(output)
        }
    }

    private static func swap(_ data: Data, into exe: URL) throws {
        let tmp = exe.deletingLastPathComponent().appending(path: ".lean.new")
        try data.write(to: tmp)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        guard rename(tmp.path, exe.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func run(_ tool: String, _ args: [String]) -> (Int32, String) {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = out
        p.standardError = out
        guard (try? p.run()) != nil else { return (-1, "could not run \(tool)") }
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: restart

    private func registerRestart() {
        Commands.shared.register("update.restart", "Restart to Finish Update", owner: id) {
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; exec open \"$0\"",
                                  Bundle.main.bundleURL.path]
            try? relaunch.run()
            NSApp.terminate(nil)
        }
    }

    private func toast(_ text: String) { App.shared?.current?.toast(text) }
}
