import Foundation
import Testing
@testable import LeanKit

@MainActor
@Suite struct AddonTests {
    func write(_ src: String) throws -> URL {
        let f = FileManager.default.temporaryDirectory.appending(path: "t\(UUID().uuidString.prefix(6)).js")
        try src.write(to: f, atomically: true, encoding: .utf8)
        return f
    }

    @Test func loadsCommandsAndRunsThem() throws {
        let f = try write("""
        export default { name: "T", commands: { "t.go": { title: "Go", key: "cmd+shift+9", run: () => console.log("ran") } } };
        """)
        let a = JSAddon(file: f, kind: .user)
        a.load()
        #expect(a.error == nil && a.name == "T" && a.commandIDs == ["t.go"])
        #expect(Commands.shared.run("t.go"))
        #expect(a.logs.last == "ran")
        a.unload()
        #expect(!Commands.shared.run("t.go"))
    }

    @Test func throwingAddonIsDisabledNotFatal() throws {
        let a = JSAddon(file: try write("export default { commands: { 'x.y': { run(){} } }, setup() { null.boom() } };"), kind: .user)
        a.load()
        #expect(a.error?.contains("TypeError") == true)
        #expect(!a.isLoaded && a.commandIDs.isEmpty)
    }

    @Test func asyncRejectionDisablesToo() throws {
        let a = JSAddon(file: try write("export default { async setup() { throw new Error('later') } };"), kind: .user)
        a.load()
        #expect(a.error?.contains("later") == true)
    }

    @Test func hookReturnsFirstResult() throws {
        let a = JSAddon(file: try write("export default { beforeNavigate({url}) { if (url.includes('x')) return {cancel: true} } };"), kind: .user)
        a.load()
        #expect((a.emit("beforeNavigate", ["url": "https://x.com"]) as? [String: Any])?["cancel"] as? Bool == true)
        #expect(a.emit("beforeNavigate", ["url": "https://a.com"]) == nil)
    }

    @Test func missingExportFails() throws {
        let a = JSAddon(file: try write("const x = 1;"), kind: .user)
        a.load()
        #expect(a.error?.contains("export default") == true)
    }

    @Test func matchPatterns() {
        let r = try! NSRegularExpression(pattern: JSAddon.matchRegex("*://*.youtube.com/*"))
        let s = "https://www.youtube.com/watch"
        #expect(r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil)
    }
}
