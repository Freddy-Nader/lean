# Checkpoint 3 — glass, top bar row, compact tabs with favicons

Files: new `Sources/LeanKit/Glass.swift`, `BrowserWindow.swift`, `Builtin/TabStrip.swift`,
`Builtin/Palette.swift`, `Tab.swift`, `Address.swift`, tests.

Reference look (user screenshots): dark window; one row at the very top level with the traffic
lights; to their right ‹ › ↻ in a small glass capsule; then the tabs as plain text items
(favicon + title, secondary colour); the focused tab is a wider glass capsule with the host centred
in primary colour; `+` in a glass circle at the far right. The page starts below that row.

## 1. Glass helper

```swift
/// Liquid Glass on macOS 26, the older blur before. Add subviews to `content`, not `view`.
@MainActor enum Glass {
    static func make(cornerRadius: CGFloat) -> (view: NSView, content: NSView)
}
```
macOS 26: `NSGlassEffectView`, `cornerRadius`, `contentView = content`. Older: `NSVisualEffectView`
(`.popover`, `.active`, layer corner radius, masks) with `content` pinned to its edges. Verify the
content view really fills the glass view on 26 (if not, pin it).

## 2. Top bar row

- Keep the window style (no toolbar; see measured facts in README). The row is vertically centred on
  the traffic lights: compute the close button's centre from the top after the window is created
  (`standardWindowButton(.closeButton)` frame converted to the content view; it is 16pt on this
  machine) and use it as the row's centre. Content (`web view`) starts at 2× that (32pt) plus 4pt.
  Bump row height so 28pt-tall items fit; if that needs a taller bar than 32pt, use 40pt and add the
  toolbar only if clicks still reach the content views — check it, do not assume.
- Nav buttons ‹ › ↻ (SF Symbols `chevron.left`, `chevron.right`, `arrow.clockwise`) in one glass
  capsule, leading edge at zoom-button right edge + 12. They run `page.back`, `page.forward`,
  `page.reload` through `Commands.shared.run`. Hidden when the window has zero tabs. Back/forward
  dimmed when `canGoBack`/`canGoForward` is false (update on `tabsChanged`).
- The top tab strip (`setEdge("top", v)`) now goes in this row, from the nav buttons' trailing edge
  to the window's trailing edge − 8, instead of a separate 30pt row under the address field. Until
  checkpoint 4 the address field is still there: put it in its own row below for now, or hide it if
  that is simpler — checkpoint 4 deletes it anyway.
- Left/right/bottom strip positions keep working: the row then holds only the nav buttons.

## 3. Compact tabs (horizontal strip)

Rewrite `TabStrip.TabButton` rendering for the horizontal case:
- Unfocused tab: 16pt favicon (fallback SF `globe`) + title, 12pt, `.secondaryLabelColor`, no
  background, ideal width 150 (priority 700), shrink evenly, min ~ favicon only. Hover: faint
  background + × as today.
- Focused tab: glass capsule (`Glass.make(cornerRadius: 14)`), height 28, ideal width 360
  (priority 700, shrinks after the others), content = favicon + `Address.displayHost(url)` centred,
  13pt, `.labelColor`. Empty-URL tab shows "New Tab".
- `+`: glass circle 28×28 pinned to the strip's trailing edge, always visible (with zero tabs it is
  the only thing in the top bar). Click → `Commands.shared.run("tab.new")` (palette with ↵ = new tab;
  in an empty window the centred palette is already there, so just focus it).
- Loading: keep a simple indicator (the existing "◌ " prefix is fine, or a small `NSProgressIndicator`
  spinner replacing the favicon).
- Vertical strip: same button with favicon + title, selected = light background as today. No glass
  capsule needed there.
- Animate width changes when focus moves (`NSAnimationContext` 0.2s on the width constraints) only if
  it is a few lines; otherwise skip and note it.

## 4. Favicons

In `Tab.swift`, no stored per-tab state:
```swift
/// Site icons by host, filled after page loads.
static var icons: [String: NSImage] = [:]
private static var tried: Set<String> = []
var favicon: NSImage? { url?.host().flatMap { Self.icons[$0] } }
```
On `didFinish`: if the host is not in `tried`, insert it, read
`document.querySelector('link[rel~="icon"]')?.href ?? ""` via `evaluateJavaScript`, fall back to
`/favicon.ico` relative to the page, fetch with `URLSession.shared`, `NSImage(data:)`, store, call
`changed()`. Main-actor `Task`; no new types.

## 5. Display host

`Address.displayHost(_ url: URL?) -> String`: host without a leading `www.`; `lean://<host>` for lean
URLs; last path component for `file:`; `""` for nil. Tests: `https://www.inkandswitch.com/essay/x?y`
→ `inkandswitch.com`, `https://news.ycombinator.com/item?id=1` → `news.ycombinator.com`,
`lean://settings` → `lean://settings`, `http://localhost:3000/a` → `localhost`, nil → `""`.

## 6. Palette glass

Palette `box`: use `Glass.make(cornerRadius: 16)`; add its subviews to `content`. Keep row
selection colour readable on glass in both light and dark.

## Acceptance

- Snapshot + orchestrator real-pixel check: one top row aligned with the traffic lights; nav capsule;
  compact tabs with favicons; focused tab capsule shows host only; `+` at far right. Zero tabs →
  only `+` (and traffic lights) in the bar, palette centred.
- Clicks on tabs, ×, +, ‹ › ↻ all work (use the dev channel and dev-state.json to confirm effects).
- `swift test` green (displayHost tests).
