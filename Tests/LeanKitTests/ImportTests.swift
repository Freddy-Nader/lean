import CommonCrypto
import Foundation
import SQLite3
import Testing
@testable import LeanKit

@MainActor
@Suite struct ImportTests {
    let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appending(path: "imp-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func exec(_ db: URL, _ sql: String) {
        var h: OpaquePointer?
        sqlite3_open(db.path, &h)
        sqlite3_exec(h, sql, nil, nil, nil)
        sqlite3_close(h)
    }

    @Test func readsChromiumHistory() throws {
        // 2026-01-01T00:00:00Z in Chromium time (µs since 1601).
        let t: Int64 = (1_767_225_600 + 11_644_473_600) * 1_000_000
        exec(dir.appending(path: "History"), """
            CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INT, last_visit_time INT, hidden INT);
            INSERT INTO urls VALUES (1,'https://a.com/','A',3,\(t),0),(2,'https://hidden.com/','H',1,\(t),1);
            """)
        let h = try BrowserImport.chromiumHistory(dir)
        #expect(h.count == 1)
        #expect(h[0]["url"] as? String == "https://a.com/" && h[0]["visits"] as? Int == 3)
        #expect(h[0]["last"] as? Double == 1_767_225_600_000)
    }

    @Test func readsChromiumBookmarks() throws {
        let json = #"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"X","url":"https://x.com/"},{"type":"folder","children":[{"type":"url","name":"Y","url":"https://y.com/"}]}]}}}"#
        try json.write(to: dir.appending(path: "Bookmarks"), atomically: true, encoding: .utf8)
        let b = try BrowserImport.chromiumBookmarks(dir)
        #expect(Set(b.compactMap { $0["url"] as? String }) == ["https://x.com/", "https://y.com/"])
    }

    @Test func decryptsV10() {
        let key = Data(repeating: 7, count: 16)
        let iv = Data(repeating: 0x20, count: 16)
        let plain = Data("session-token".utf8)
        var out = Data(count: plain.count + 16)
        var moved = 0
        let n = out.count
        _ = out.withUnsafeMutableBytes { o in plain.withUnsafeBytes { p in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    k.baseAddress, 16, v.baseAddress, p.baseAddress, plain.count, o.baseAddress, n, &moved)
        } } } }
        let enc = Data("v10".utf8) + out.prefix(moved)
        #expect(BrowserImport.decrypt(enc, key: key) == plain)
        #expect(BrowserImport.decrypt(Data("v11xxx".utf8), key: key) == nil)
    }
}
