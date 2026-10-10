import AppKit
import Testing
@testable import LeanKit

@MainActor
@Suite struct KeyTests {
    @Test func parsesModifiersInAnyOrder() {
        #expect(Key("cmd+shift+t") == Key("shift+cmd+T"))
        #expect(Key("opt+n") == Key("alt+n"))
    }
    @Test func describesWithGlyphs() {
        #expect(Key("cmd+shift+c")?.description == "⇧⌘C")
        #expect(Key("ctrl+tab")?.description == "⌃⇥")
    }
    @Test func rejectsModifierOnly() { #expect(Key("cmd+shift") == nil) }

    @Test func registryRunsAndUserCanRebind() {
        let c = Commands.shared
        var hits = 0
        c.register("test.hit", "Hit", keys: ["cmd+j"]) { hits += 1 }
        #expect(c.run("test.hit"))
        #expect(hits == 1)
        #expect(c.key(for: "test.hit") == "⌘J")
        #expect(!c.run("test.missing"))
        c.unregister("test.hit")
    }
}
