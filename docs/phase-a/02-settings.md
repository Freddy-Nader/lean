# Checkpoint 2 — declared settings, lean://settings, ⌘,, palette coverage

Files: `Settings.swift`, `KernelCommands.swift`, `Addons/AddonsPage.swift` (rename),
`Tab.swift`, `App.swift`, `Builtin/Palette.swift`, `Builtin/TabStrip.swift`, `Addons/JSAddon.swift`,
`Addons/Prelude.swift`, wherever add-on unload cleans up per-owner state (grep `PaletteGroups.shared.removeAll`),
`API.md`, tests.

## Principle

Declaring is the only way to add a user-facing thing, and declaring puts it in the palette:
- actions → `Commands.register` (already listed in the palette automatically);
- settings → `Settings.declare` (new; listed on `lean://settings` **and** in the palette);
- switched-off add-ons → listed in the palette as "Turn On <name>" from data that already exists.

## 1. `Settings.declare`

```swift
/// A user-facing setting. Declaring it is what puts it on lean://settings and in the palette.
public struct Declared {
    public let key: String, title: String, icon: String
    /// (label, value) choices; empty = a folder picked with an open panel.
    public let options: [(label: String, value: String)]
    let owner: String
}
public static let changed = Notification.Name("lean.settingsChanged")   // object: key, or nil after reload
private(set) var declared: [Declared] = []
func declare(_ key: String, _ title: String, icon: String = "gearshape", options: [(String, String)] = [], owner: String = "kernel")
func undeclare(owner: String)
/// Open panel for a folder setting.
func chooseFolder(_ key: String)
```

- Re-declaring a key replaces it. `set()` posts `changed` with the key; `reload()` posts with nil.
- Kernel declares (in `KernelCommands.register` or at App start): `downloads.folder` "Downloads
  Folder" (folder) and `search.template` "Search Engine" with the five engines now hard-coded in
  `Palette.settingItems()` (Google, DuckDuckGo, Kagi, Perplexity, Bing).
- `TabStrip.load()` declares `tabstrip.position` "Tab Position" (top/bottom/left/right/hidden, owner
  `tabstrip`); `unload()` undeclares. TabStrip observes `Settings.changed` and re-attaches when the key
  is `tabstrip.position` or nil, so changing it from the page or a JS add-on works. The `position`
  setter just writes the setting.
- JS: `ctx.settings.declare(key, { title, options })` where options are strings or `{label, value}`;
  wire through `Prelude.swift` + a `native.settingDeclare(key, title, optionsJSON)` block in
  `JSAddon.swift`, owner = add-on id; undeclare on add-on unload next to `PaletteGroups.removeAll`.
  Add `settings.set(key, value)` only if trivial (it is: `Settings.shared.set`). Document both in
  `API.md` (the `settings` row) with a one-line rule: "declare a setting so it shows in Settings and
  the palette".

## 2. Palette uses declarations

- Replace the hard-coded `settingItems()` with one built from `Settings.shared.declared`:
  choice → push a Level listing options (✓ accessory on the current value), folder → `chooseFolder`.
  Subtitle = current value's label (or path).
- Drop the "Add-ons" and "Edit Keybindings" pseudo-settings: they become commands (§3) and show up
  under Commands.
- New palette group "Add-ons" (only when the query is non-empty): every add-on that is switched off
  (JS: `AddonHost.shared.addons`, Swift: `SwiftAddons.all`, check `AddonHost.shared.isEnabled(id, kind)`),
  item title `"Turn On <name>"`, subtitle = summary, icon `puzzlepiece.extension`, run =
  `AddonHost.shared.setEnabled(id, true)` then toast `"<name> turned on"`. Ranked with the same
  `ranked()` helper, matching name and summary, so typing "import" finds the Import add-on.

## 3. Commands

- `settings.open` "Settings", keys `cmd+,`: select an existing tab whose URL scheme is `lean`, else
  open `lean://settings` in a new foreground tab (works in a zero-tab window).
- `addons.open` (⌘⇧A) opens `lean://settings#addons` with the same reuse rule.
- `keys.edit` "Edit Keybindings": the code currently inside the palette's keybindings item.
- ⌘, must actually fire: check `Commands`/key map handles the `,` key (see `Key` parsing and
  `Tests/LeanKitTests/KeyTests.swift`); add a KeyTests case for `cmd+,`. Also check the app menu does
  not swallow ⌘, (there is no Preferences item; keep it that way).

## 4. lean://settings page

Rename `AddonsPage` → `SettingsPage` (file, type, references, `static let url = lean://settings`).
Any `lean://` URL renders the same page. Layout, top to bottom, same CSS style as today:

- `<h1>Settings</h1>`
- **General**: one row per declared setting: title, then a `<select>` for choices (current value
  selected) or the path plus a "Choose…" button for folders. Changing posts
  `{action: "set", key, value}`; "Choose…" posts `{action: "choose", key}`. Plus a row "Keybindings"
  with an "Edit…" button posting `{action: "command", id: "keys.edit"}`.
- `<h2 id=addons>Add-ons</h2>`: today's add-on list unchanged.
- Slots table unchanged.

Message handler: accept only from `lean:` frames (as now). `set` only for declared keys (trust
boundary: a page cannot write arbitrary settings). `command` only for `keys.edit`. Re-render open
settings pages when `Settings.changed` fires (reuse `refresh()`).

## 5. Tests

- `Settings.declare` replace-by-key and `undeclare(owner:)`.
- Palette-independent check that kernel declares `downloads.folder` and `search.template` after
  `KernelCommands.register` (if registering needs an `App`, test `declare` alone and note it).
- `Key("cmd+,")` parses.

## Acceptance

- ⌘, from a page or from an empty window opens `lean://settings`, showing General + Add-ons.
- Changing Search Engine on the page persists to `~/.config/lean/settings.json` and the palette
  shows the new value; changing Tab Position on the page moves the strip.
- Palette: typing "search engine", "downloads", "tab position" finds the settings; "import" finds
  the Import add-on (switch it off on the page first to test "Turn On Import", then switch it back
  on — the user had it enabled).
