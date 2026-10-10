import Testing
@testable import LeanKit

@MainActor
@Suite struct BrowserWindowTests {
    @Test func startsWithoutTabs() {
        let w = BrowserWindow()
        #expect(w.tabs.isEmpty && w.tab == nil)
    }

    @Test func closingLastTabKeepsWindow() {
        let w = BrowserWindow()
        var closed = false
        w.onClose = { closed = true }
        w.add(Tab(), select: true)
        #expect(w.tab != nil)
        w.close(at: 0)
        #expect(w.tabs.isEmpty && w.tab == nil && !closed)
    }

    @Test func backgroundTabInEmptyWindowIsSelected() {
        let w = BrowserWindow()
        w.add(Tab(), select: false)
        #expect(w.tab === w.tabs[0])
    }
}
