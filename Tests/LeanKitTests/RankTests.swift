import Foundation
import Testing
@testable import LeanKit

@Suite struct RankTests {
    @Test func prefixBeatsWordStartBeatsScattered() {
        let p = Rank.match("tab", "Tabs on Top")!, w = Rank.match("tab", "Move Tab Right")!
        #expect(p > w)
        #expect(Rank.match("tab", "GitHub · Change is constant") == nil)
        #expect(Rank.match("xyz", "Tabs") == nil)
        #expect(Rank.match("nt", "New Tab") != nil)
    }

    @MainActor @Test func frecencyDecaysAndForgets() {
        let r = Rank()
        let key = "test:\(UUID())"
        r.pick(key, now: Date(timeIntervalSinceNow: -30 * 86_400))
        #expect(abs(r.frecency(key) - 0.5) < 0.01)        // one half-life ago
        r.pick(key)
        #expect(r.frecency(key) > 1.4)
        r.forget(key)
        #expect(r.frecency(key) == 0)
    }
}
