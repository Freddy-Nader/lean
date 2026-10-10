import AppKit
import CommonCrypto
import SQLite3
import WebKit

/// Import from other browsers (optional Swift add-on). Chromium browsers (Arc, Brave, Chrome, Comet,
/// Dia, …) share one format; Safari needs Full Disk Access. History and bookmarks go to whichever
/// add-on handles the `import` hook (the history add-on by default); cookies go straight into
/// WebKit's store so you stay logged in. Passwords are never imported: they stay in Apple Passwords.
@MainActor
final class BrowserImport: SwiftAddon {
    let id = "import", name = "Import", kind = JSAddon.Kind.optional
    let summary = "Bring history, bookmarks and logged-in sessions over from Chromium browsers and Safari."

    struct Source {
        let name: String
        let profile: URL          // folder holding History / Bookmarks / Cookies
        let keychain: String?     // "<Name> Safe Storage" for Chromium cookie decryption
        var safari: Bool { keychain == nil }
    }

    func load() throws {
        Commands.shared.register("import.run", "Import from Another Browser…", owner: id) { [weak self] in self?.wizard() }
    }

    func unload() {}

    // MARK: discovery

    static func sources() -> [Source] {
        let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        let chromium: [(String, String, String)] = [
            ("Arc", "Arc/User Data", "Arc Safe Storage"),
            ("Brave", "BraveSoftware/Brave-Browser", "Brave Safe Storage"),
            ("Chrome", "Google/Chrome", "Chrome Safe Storage"),
            ("Comet", "Comet", "Comet Safe Storage"),
            ("Dia", "Dia/User Data", "Dia Safe Storage"),
            ("Edge", "Microsoft Edge", "Microsoft Edge Safe Storage"),
            ("Vivaldi", "Vivaldi", "Vivaldi Safe Storage"),
        ]
        var out: [Source] = chromium.compactMap { name, dir, key in
            let p = support.appending(path: dir).appending(path: "Default")
            return FileManager.default.fileExists(atPath: p.appending(path: "History").path) ? Source(name: name, profile: p, keychain: key) : nil
        }
        let safari = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari")
        out.append(Source(name: "Safari", profile: safari, keychain: nil))
        return out
    }

    // MARK: UI

    private func wizard() {
        let sources = Self.sources()
        let alert = NSAlert()
        alert.messageText = "Import from another browser"
        alert.informativeText = "Passwords are not imported; they stay in Apple Passwords. Cookies need your permission in the next dialog (macOS asks for the browser's Keychain item)."
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: sources.map(\.name))
        let history = NSButton(checkboxWithTitle: "History", target: nil, action: nil)
        let bookmarks = NSButton(checkboxWithTitle: "Bookmarks (searchable in the palette)", target: nil, action: nil)
        let cookies = NSButton(checkboxWithTitle: "Logged-in sessions (cookies)", target: nil, action: nil)
        [history, bookmarks, cookies].forEach { $0.state = .on }
        let stack = NSStackView(views: [popup, history, bookmarks, cookies])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 110)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let src = sources[popup.indexOfSelectedItem]
        run(src, history: history.state == .on, bookmarks: bookmarks.state == .on, cookies: cookies.state == .on)
    }

    func run(_ src: Source, history: Bool, bookmarks: Bool, cookies: Bool) {
        var report: [String] = []
        do {
            if history {
                let items = src.safari ? try Self.safariHistory(src.profile) : try Self.chromiumHistory(src.profile)
                AddonHost.shared.emit("import", ["kind": "history", "items": items])
                report.append("\(items.count) history entries")
            }
            if bookmarks {
                let items = src.safari ? try Self.safariBookmarks(src.profile) : try Self.chromiumBookmarks(src.profile)
                AddonHost.shared.emit("import", ["kind": "bookmarks", "items": items])
                report.append("\(items.count) bookmarks")
            }
            if cookies, let key = src.keychain {
                let list = try Self.chromiumCookies(src.profile, keychainService: key)
                let store = WKWebsiteDataStore.default().httpCookieStore
                list.forEach { store.setCookie($0) }
                report.append("\(list.count) cookies")
            } else if cookies {
                report.append("Safari cookies are not supported yet")
            }
            App.shared?.current?.toast("Imported from \(src.name): " + report.joined(separator: ", "))
        } catch {
            let a = NSAlert()
            a.messageText = "Import from \(src.name) failed"
            a.informativeText = "\(error)" + (src.safari ? "\n\nSafari's data needs Full Disk Access: System Settings → Privacy & Security → Full Disk Access → add lean." : "")
            a.runModal()
        }
    }

    // MARK: Chromium

    struct ImportError: Error, CustomStringConvertible { let description: String }

    /// Chromium keeps its databases locked while running, so read a copy.
    static func query(_ db: URL, _ sql: String, _ row: (OpaquePointer) -> Void) throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "lean-import-\(UUID().uuidString).db")
        try FileManager.default.copyItem(at: db, to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var h: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw ImportError(description: "cannot open \(db.lastPathComponent)") }
        defer { sqlite3_close(h) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else {
            throw ImportError(description: String(cString: sqlite3_errmsg(h)))
        }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW { row(st!) }
    }

    static func text(_ st: OpaquePointer, _ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }

    /// Chromium time: microseconds since 1601-01-01 → ms since 1970.
    static func chromeTime(_ t: Int64) -> Double { Double(t / 1000) - 11_644_473_600_000 }

    static func chromiumHistory(_ p: URL) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        try query(p.appending(path: "History"),
                  "SELECT url, title, visit_count, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT 5000") { st in
            out.append(["url": text(st, 0), "title": text(st, 1), "visits": Int(sqlite3_column_int(st, 2)),
                        "last": chromeTime(sqlite3_column_int64(st, 3))])
        }
        return out
    }

    static func chromiumBookmarks(_ p: URL) throws -> [[String: Any]] {
        let f = p.appending(path: "Bookmarks")
        guard let d = try? Data(contentsOf: f) else { return [] }
        let json = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        var out: [[String: Any]] = []
        func walk(_ node: [String: Any]) {
            if node["type"] as? String == "url", let url = node["url"] as? String {
                out.append(["url": url, "title": node["name"] as? String ?? ""])
            }
            (node["children"] as? [[String: Any]])?.forEach(walk)
        }
        (json?["roots"] as? [String: Any])?.values.compactMap { $0 as? [String: Any] }.forEach(walk)
        return out
    }

    static func chromiumCookies(_ p: URL, keychainService: String) throws -> [HTTPCookie] {
        let key = try derivedKey(keychainService)
        var version = 0
        try query(p.appending(path: "Cookies"), "SELECT value FROM meta WHERE key = 'version'") { version = Int(text($0, 0)) ?? 0 }
        var out: [HTTPCookie] = []
        try query(p.appending(path: "Cookies"),
                  "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly FROM cookies") { st in
            var value = text(st, 2)
            if value.isEmpty, let blob = sqlite3_column_blob(st, 3) {
                let enc = Data(bytes: blob, count: Int(sqlite3_column_bytes(st, 3)))
                guard var plain = decrypt(enc, key: key) else { return }
                if version >= 24, plain.count >= 32 { plain = plain.dropFirst(32) }   // SHA-256 of the host, prepended since Chromium 130
                value = String(decoding: plain, as: UTF8.self)
            }
            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: text(st, 0), .name: text(st, 1), .value: value, .path: text(st, 4),
            ]
            let exp = sqlite3_column_int64(st, 5)
            if exp > 0 { props[.expires] = Date(timeIntervalSince1970: chromeTime(exp) / 1000) }
            if sqlite3_column_int(st, 6) != 0 { props[.secure] = "TRUE" }
            if sqlite3_column_int(st, 7) != 0 { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let c = HTTPCookie(properties: props) { out.append(c) }
        }
        return out
    }

    /// macOS shows its own prompt here: "lean wants to use … '<Name> Safe Storage'".
    static func derivedKey(_ service: String) throws -> Data {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let pw = item as? Data else {
            throw ImportError(description: "no access to Keychain item “\(service)”")
        }
        var key = Data(count: kCCKeySizeAES128)
        let salt = Data("saltysalt".utf8)
        let ok = key.withUnsafeMutableBytes { k in
            pw.withUnsafeBytes { p in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress, pw.count, s.baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, k.baseAddress, kCCKeySizeAES128)
                }
            }
        }
        guard ok == kCCSuccess else { throw ImportError(description: "key derivation failed") }
        return key
    }

    /// "v10" + AES-128-CBC, IV of 16 spaces, PKCS7 padding.
    static func decrypt(_ enc: Data, key: Data) -> Data? {
        guard enc.count > 3, enc.prefix(3) == Data("v10".utf8) else { return nil }
        let body = enc.dropFirst(3)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var out = Data(count: body.count + kCCBlockSizeAES128)
        var moved = 0
        let outCount = out.count
        let st = out.withUnsafeMutableBytes { o in
            body.withUnsafeBytes { b in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, v.baseAddress, b.baseAddress, body.count, o.baseAddress, outCount, &moved)
                    }
                }
            }
        }
        return st == kCCSuccess ? out.prefix(moved) : nil
    }

    // MARK: Safari (needs Full Disk Access)

    static func safariHistory(_ p: URL) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        try query(p.appending(path: "History.db"), """
            SELECT i.url, v.title, i.visit_count, MAX(v.visit_time) FROM history_items i
            JOIN history_visits v ON v.history_item = i.id GROUP BY i.id ORDER BY MAX(v.visit_time) DESC LIMIT 5000
            """) { st in
            // Safari time: seconds since 2001-01-01.
            out.append(["url": text(st, 0), "title": text(st, 1), "visits": Int(sqlite3_column_int(st, 2)),
                        "last": (sqlite3_column_double(st, 3) + 978_307_200) * 1000])
        }
        return out
    }

    static func safariBookmarks(_ p: URL) throws -> [[String: Any]] {
        guard let d = try? Data(contentsOf: p.appending(path: "Bookmarks.plist")),
              let root = try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else {
            throw ImportError(description: "cannot read Safari bookmarks")
        }
        var out: [[String: Any]] = []
        func walk(_ n: [String: Any]) {
            if let url = n["URLString"] as? String {
                out.append(["url": url, "title": (n["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""])
            }
            (n["Children"] as? [[String: Any]])?.forEach(walk)
        }
        walk(root)
        return out
    }
}
