import Foundation
import Testing
@testable import LeanKit

@MainActor
@Suite struct SettingsTests {
    @Test func declareReplacesByKeyAndUndeclaresByOwner() {
        let s = Settings.shared
        s.declare("t.a", "A", owner: "t")
        s.declare("t.a", "A2", options: [("x", "1")], owner: "t")
        s.declare("t.b", "B", owner: "u")
        #expect(s.declared.filter { $0.key == "t.a" }.map(\.title) == ["A2"])
        s.undeclare(owner: "t")
        #expect(!s.declared.contains { $0.owner == "t" } && s.declared.contains { $0.key == "t.b" })
        s.undeclare(owner: "u")
    }

    @Test func pagesMayOnlyPickDeclaredOptions() {
        let s = Settings.shared
        s.declareKernel()
        #expect(s.accepts("search.template", "https://kagi.com/search?q=%s"))
        #expect(!s.accepts("search.template", "https://evil.example/?q=%s"))
        #expect(!s.accepts("downloads.folder", "/tmp"))   // folder settings change only through the open panel
        #expect(!s.accepts("nope", "x"))
    }

    @Test func kernelDeclaresItsSettings() {
        Settings.shared.declareKernel()
        let keys = Settings.shared.declared.map(\.key)
        #expect(keys.contains("downloads.folder") && keys.contains("search.template"))
        #expect(Settings.shared.declared.first { $0.key == "search.template" }?.options.count == 5)
    }
}

@MainActor
@Suite struct JSSettingsTests {
    @Test func jsDeclareShowsUpAndUnloadRemovesIt() throws {
        let f = FileManager.default.temporaryDirectory.appending(path: "s\(UUID().uuidString.prefix(6)).js")
        try "export default { setup({ settings }) { settings.declare('js.k', { title: 'JS K', options: ['a', { label: 'B', value: 'b' }] }) } };".write(to: f, atomically: true, encoding: .utf8)
        let a = JSAddon(file: f, kind: .user)
        a.load()
        let d = Settings.shared.declared.first { $0.key == "js.k" }
        #expect(d?.title == "JS K" && d?.options.map(\.value) == ["a", "b"])
        a.unload()
        #expect(!Settings.shared.declared.contains { $0.key == "js.k" })
    }
}
