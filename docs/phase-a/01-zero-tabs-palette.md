# Checkpoint 1 — zero tabs, palette prompt, ⌘T, snapshot

Files: `BrowserWindow.swift`, `KernelCommands.swift`, `FindBar.swift`, `App.swift`, `Dev.swift`,
`Builtin/Palette.swift`, `Addons/JSAddon.swift` (only if needed), `addons/default/session.js`, tests.

## 1. Active tab becomes optional

- `BrowserWindow.tab` → `var tab: Tab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }`.
- Fix every use (grep `\.tab\b`, `tab\.webView`, `tab\.url`): `KernelCommands` (`web { }` helper must
  no-op without a tab; `rules.togglePause`), `Dev.swift` eval, `Palette.swift` (`close`, `tabItems`,
  `webItem`), `FindBar` (`webView: () -> WKWebView?`; `next` / `close` use optional chaining).
- `BrowserWindow.init` no longer adds a `Tab()`. A window can have zero tabs.
- `close(at:)`: when the last tab closes, do **not** close the window. Clear `content`, set
  `activeIndex = 0`, `window?.title = "lean"`, post `tabsChanged`.
- `add(_:select:)`: if `tabs` was empty, always select the new tab (background opens into an empty
  window must still show it).
- `load(_ input:)`: with no tab, `open(url, background: false)`; otherwise load in the active tab.
- `tab.close` (⌘W) on a window with zero tabs closes the window.
- `App.newWindow(url:)`: if no url, do nothing extra (the palette shows itself, see §3).

## 2. One prompt hook instead of `addressDown`

Replace `static var addressDown: ((BrowserWindow, String) -> Void)?` with

```swift
/// Set by the palette add-on: opens it on this window with `text`; `newTab` makes ↵ open a new tab.
static var prompt: ((BrowserWindow, _ text: String, _ newTab: Bool) -> Void)?
```

Kernel callers:
- ↓ in the address field (still exists until checkpoint 4): `prompt(self, text, false)`.
- `tab.new` (⌘T): `if let p = Self.prompt { p(w, "", true) } else { w.add(Tab(), select: true) }`
  (fallback keeps the browser usable with the palette add-on switched off).

## 3. Palette: new-tab mode and centered empty-window mode

In `Palette.swift`:
- `open(in:query:newTab:)` stores `newTab`. `webItem`: primary action loads in the active tab unless
  `newTab` is true **or** the host window has no tab, in which case it calls `w.open(u, background: false)`.
  ⌘↵ (alt) does the opposite of the primary.
- **Centered mode** = host window has zero tabs. Box is centred: replace the fixed
  `box.top = backdrop.top + 72` with two constraints and toggle them on open: normal = top 72;
  centered = `box.top = backdrop.centerY - 60` (field sits a bit above the middle, results grow down).
- In centered mode Esc on the root level clears the field (does not close), backdrop click does
  nothing.
- `activate`: hide, run the item, then `if host has no tabs { reopen centered }` (a command that
  does not create a tab must not leave an empty window with nothing in it).
- Observe `BrowserWindow.opened` and `BrowserWindow.tabsChanged` in `load()`, remove in `unload()`:
  - window has zero tabs and the palette is not already open on it → `open(in: w)` (covers launch
    and closing the last tab).
  - palette is open centered on `w` and `w` now has tabs → `close()` (e.g. session restore).
  `tabsChanged` fires often (loading progress); keep the handler cheap.
- `close()` restores first responder to the active tab's web view if there is one.
- Palette is one singleton view: with two empty windows it moves to whichever triggered last.
  Acceptable; leave a `// shortcut:` comment.

## 4. session.js

`onReady` currently relies on a blank start tab. New logic: collect `fresh = saved.filter(u => !open.has(u))`;
if there is no active tab and `fresh` is non-empty, open `fresh.shift()` in the foreground, then open
the rest in **reverse** in the background (background tabs insert after the active one, so order is
kept). Delete the `blank` handling. Keep the `ready` guard.

## 5. Dev snapshot command

In `Dev.swift`, add a dev-only command `snapshot <path>`: renders the current window's
`contentView` with `bitmapImageRepForCachingDisplay(in:)` + `cacheDisplay(in:to:)` and writes PNG
to `<path>`. Only reachable through the existing LEAN_DEV channel. Add one line to README's dev
section.

## 6. Tests (Swift Testing, `@MainActor`, match `Tests/LeanKitTests` style)

- A `BrowserWindow()` starts with zero tabs and `tab == nil`.
- Adding then closing the only tab leaves the window with zero tabs (window not closed: `onClose` not called).
- Adding a background tab to an empty window selects it.
If creating `BrowserWindow` in tests is impossible (needs NSApp), say so in STATUS.md and test what
is testable.

## Acceptance

- Launch with no saved session → window with only the tab strip `+`, palette centred, field focused.
  Type `wikipedia.org` ↵ → one tab opens with that page, palette gone.
- ⌘T with tabs → palette at the top; type a domain ↵ → opens in a **new** tab.
- ⌘W on the last tab → window stays, centred palette returns. ⌘W again → window closes.
- Session add-on restores saved tabs in the original order.
- `swift test` green; snapshot PNG shows the centred palette.
