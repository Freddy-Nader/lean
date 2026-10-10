# lean add-on API

The contract add-ons (and the AI writing them) rely on. Anything not here does not exist.
Check a file with `lean --check <file.js>` before using it.

## Where add-ons live

- `~/.config/lean/addons/<id>.js`: yours. The file name is the id (lowercase-with-hyphens). Saving the
  file reloads it in the running browser (hot reload); tabs stay open.
- Shipped with the app: `addons/default/` (on unless disabled) and `addons/optional/` (off unless
  enabled). A file in your folder with the same id overrides the shipped one: copy it there to fork it.
- `lean://settings` (⌘, ; ⌘⇧A jumps to its add-ons section) shows the general settings and lists every add-on with its switch, commands,
  last error and log, and which add-on provides each slot.
- Storage: `~/.config/lean/addons/.<id>.data.json`.
- Errors never crash the browser: a throw (sync or async, host or page) disables that add-on and shows
  the error on the add-ons page. Fix the file and save; it reloads.

## Shape of a JS add-on

```js
// ~/.config/lean/addons/reader.js
export default {
  name: "Reader",
  description: "Strip a page down to its article text.",

  commands: {
    "reader.toggle": {                    // ids start with the add-on id
      title: "Toggle Reader Mode",        // shown in the palette
      key: "cmd+shift+r",                 // default; keys.json can override
      run: ({ tabs }) => tabs.active().send("toggle"),
    },
  },

  setup(ctx) {},                 // after every load (launch and hot reload)
  onReady(_, ctx) {},            // once per launch, after the first window opens

  // hooks: (payload, ctx)
  onTabCreated(tab, ctx) {},
  onTabLoad(tab, ctx) {},        // tab = { id, url, title }
  onTabClosed(tab, ctx) {},
  onMessage({ tab, event, data }, ctx) {},       // from this add-on's page code
  beforeNavigate({ url, tab }, ctx) {},          // return { cancel: true } or { redirect: url }
  beforeDownload({ url, filename }, ctx) {},     // return { cancel: true } or { path: "~/…" }
  onImport({ kind, items }, ctx) {},             // from the import add-on: kind "history" | "bookmarks"

  // injected into matching pages, in this add-on's own isolated world
  page: {
    match: ["*://*/*"],          // Chrome-style match patterns; "<all_urls>" works too
    runAt: "end",                // "start" (before the page's scripts) | "end"
    run({ on, emit, data }) {
      on("toggle", () => document.body.classList.toggle("lean-reader"));
    },
  },
};
```

## Context (`ctx`), passed to `run`, `setup` and every hook

| Namespace | Calls |
|---|---|
| `tabs` | `active()`, `list()`, `open(url, { background })`, `close(id)`, `focus(id)`, `onCreated/onLoad/onClosed(fn)` |
| tab object | `id`, `url`, `title`, `eval(fn, ...args)` → Promise, `send(event, data)`, `reload()`, `navigate(url)`, `close()`, `focus()` |
| `keys` | `bind(key, commandId)`, `unbind(key)` (runtime; keys.json still wins) |
| `palette` | `addGroup(name, (query) => [{ title, subtitle, url, run }])`; rows with a `url` open like typed addresses (new tab after ⌘T, ⌘↵ the other way), and `run` still runs first |
| `ui` | `toast(text)`, `copy(text)`, `open(pathOrUrl, { reveal })` |
| `storage` | `get(key)`, `set(key, value)`, `all()` (JSON values, per add-on) |
| `settings` | `get(key)` (e.g. `downloads.folder`, `search.template`), `set(key, value)`, `declare(key, { title, options })` (options: strings or `{label, value}`). Declare a setting so it shows in Settings and the palette. |
| `net` | `fetch(url, { method, headers, body })` → `{ status, ok, text(), json() }` |
| `rules` | `add(id, contentBlockerJSON)`, `remove(id)`, `bundled()` (the shipped EasyList lists) |
| `rank` | `match(query, text)`, `score(query, text, key)`, `pick(key)`, `forget(key)` (the kernel's frecency ranking) |
| `downloads` | `list()` → `[{ url, path, done, failed }]`, newest first |
| `page` | `setData(obj)`: becomes `data` in this add-on's page code on the next page loads |
| `slots` | `provide(name, impl)`: replace a kernel subsystem (below) |
| `hooks` | `on(name, fn)`: same hooks as the `on…` fields |
| `app` | `justLaunched` (true in the first seconds after launch) |

Host globals: `console.log/error` (shown in the add-ons page log), `setTimeout`, `URL`,
`URLSearchParams` (absolute URLs), and standard JavaScript. There is no DOM and no `fetch` in the
host: use page code for the DOM and `ctx.net.fetch` for the network.

## Page code

`page.run({ on, emit, data })` runs in every matching page, in an isolated world: it sees and changes
the page's DOM but not the page's JavaScript variables, and no other add-on can see it.

- `on(event, fn)`: receive `tab.send(event, data)` from the host.
- `emit(event, data)`: send to the host; arrives as `onMessage({ tab, event, data })`.
- `data`: whatever the host last passed to `ctx.page.setData()`.

## Slots: replacing a subsystem

| Slot | Default | JS provider shape |
|---|---|---|
| `search` | Google, or the `search.template` setting | `{ url(query) → string }` |
| `downloads` | `downloads.folder` setting | `{ destination({ url, filename }) → path }` |
| `palette`, `tabstrip` | Swift add-ons | native only |
| `history`, `session`, `newtab`, `suggest` | reserved | — |

```js
// DuckDuckGo instead of Google
export default {
  name: "DuckDuckGo",
  setup({ slots }) {
    slots.provide("search", { url: (q) => "https://duckduckgo.com/?q=" + encodeURIComponent(q) });
  },
};

// downloads into a dated folder
export default {
  name: "Dated Downloads",
  beforeDownload({ filename }) {
    return { path: `~/Downloads/${new Date().toISOString().slice(0, 10)}/${filename}` };
  },
};
```

## Swift add-ons

For what JavaScript cannot do: native UI, files, Keychain, SQLite. One file in
`Sources/LeanKit/Builtin/`, a class conforming to `SwiftAddon`, listed in `SwiftAddons.all`; needs
`./build.sh`. Examples: `Palette.swift`, `TabStrip.swift`, `BrowserImport.swift`.

```swift
@MainActor
final class Indexer: SwiftAddon {
    let id = "indexer", name = "Indexer", kind = JSAddon.Kind.optional
    let summary = "Search local files from the palette."
    func load() throws {
        Commands.shared.register("indexer.search", "Search Local Files", keys: ["cmd+shift+f"], owner: id) { /* … */ }
    }
    func unload() {}
}
```

## Rules for add-on authors

- One file per add-on. No imports between add-ons; talk through hooks and slots.
- Never edit kernel files (`Sources/LeanKit/*.swift` outside `Builtin/`) to make an add-on work. If the
  API is missing something, say so; that is a kernel change for the maintainer to decide.
- Command ids are `<addon-id>.<verb>`.
- Debounce writes (`setTimeout`) when reacting to frequent hooks like `onTabLoad`.
- Run `lean --check <file>` before saying an add-on is done.
