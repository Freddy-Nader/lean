# Checkpoint 4 — the focused tab is the address field

Files: `BrowserWindow.swift`, `KernelCommands.swift`, `Builtin/TabStrip.swift`, `Builtin/Palette.swift`,
`App.swift`, `README.md`, `API.md` (if it mentions the address bar), `SPEC.md` (one-line note),
`PROGRESS.md`.

## 1. Delete the address field

Remove `address` (NSTextField), its delegate code and layout from `BrowserWindow`. `BrowserWindow`
stops conforming to `NSTextFieldDelegate` if nothing else needs it. `refresh(_:)` keeps
`window?.title = t.title`.

## 2. Hook

```swift
/// Set by the tab strip: turns the focused tab into an address field. Returns false if it can't
/// (strip hidden, no tab), and the kernel falls back to the palette.
static var editAddress: ((BrowserWindow) -> Bool)?
```
`focusAddress()`: `if Self.editAddress?(self) == true { return }` else
`Self.prompt?(self, tab?.url?.absoluteString ?? "", false)`. `address.focus` (⌘L) calls it. A selected
tab with no URL (palette add-on off fallback) also calls it.

## 3. Editing inside the focused tab (TabStrip)

- `TabStrip.load()` sets `BrowserWindow.editAddress`, `unload()` clears it.
- Editing replaces the focused tab's host label with a borderless `NSTextField` (same font, no focus
  ring) holding the full URL, all selected, first responder.
- ↵ → `w.load(text)`, end editing. Esc → end editing, web view first responder. ↓ →
  `BrowserWindow.prompt?(w, text, false)` (opens the palette with the typed text; same as before).
  Focus lost (click elsewhere) → end editing without loading.
- The strip re-renders on every `tabsChanged` (loading progress fires many): while editing, skip
  re-rendering that window's strip and render once editing ends. Do not lose typed text.
- Works for the vertical strip too (field replaces the selected tab's label).

## 4. Docs

- README keybindings/dev sections: ⌘L edits the focused tab, ⌘T opens the palette, ⌘, opens
  settings, snapshot dev command.
- PROGRESS.md: add a row "10 | Phase A: glass top bar, zero tabs, palette-first, settings page | done <hash>"
  and keep the "Not built yet" line accurate (NL pills still not built).
- SPEC.md: only fix statements that are now false (address bar, lean://addons only). One line each.

## Acceptance

- No address field anywhere. ⌘L on a page → focused tab shows the full URL selected; type
  `apple.com` ↵ → loads in that tab, tab shows `apple.com` again.
- ⌘L, Esc → back to host, page focused. ⌘L, type `swift`, ↓ → palette open with `swift`.
- Tab strip hidden (`tabstrip.hide`) → ⌘L opens the palette prefilled with the URL.
- Full regression pass of checkpoints 1–3 acceptance lists; `swift test` green.
