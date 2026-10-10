# lean add-on API (draft)

The only contract add-ons, and the AI writing them, rely on. Anything not here does not exist.

## Where add-ons live

- `~/.config/lean/addons/<id>.js` — yours. The file name is the id. Loads on save (hot reload).
- Shipped: `addons/default/` (on unless disabled) and `addons/optional/` (off unless enabled). A file in
  your folder with the same id overrides the shipped one: copy it there to fork it.
- `lean://addons` (⌘⇧A) lists every add-on with its switch, commands, last error and log.
- Storage lives in `~/.config/lean/addons/.<id>.data.json`.

## JS add-on shape

```js
// ~/.config/lean/addons/reader.js
export default {
  id: "reader",
  name: "Reader mode",
  description: "Strip a page down to its article text.",

  commands: {
    "reader.toggle": {
      title: "Toggle reader mode",
      key: "cmd+shift+r",          // default; keys.json can override
      run: async ({ tabs }) => tabs.active().send("toggle"),
    },
  },

  // runs in the host JSContext; every hook also gets the context as its second argument
  setup(ctx) {},                 // once, after load (and after every hot reload)
  onReady(_, ctx) {},            // once per launch, after the first window opens
  onTabLoad(tab, ctx) {},
  onTabCreated(tab) {},
  onTabClosed(tab) {},

  // injected into matching pages, in an isolated content world
  page: {
    match: ["*://*/*"],
    runAt: "end",                  // "start" | "end"
    run({ on }) {
      on("toggle", () => document.body.classList.toggle("lean-reader"));
    },
  },
};
```

## Host API (`ctx`, passed to `run` and handlers)

| Namespace | Calls |
|---|---|
| `tabs` | `active()`, `list()`, `open(url, {background})`, `close(id)`, `focus(id)`, `onCreated/onLoad/onClosed(fn)` |
| `tab` (object) | `id`, `url`, `title`, `eval(fn, ...args)`, `send(event, data)`, `reload()`, `navigate(url)` |
| `keys` | `bind(key, commandId)`, `unbind(key)` |
| `palette` | `addGroup(name, provider)` where `provider(query)` returns `[{title, subtitle, icon, run}]` |
| `ui` | `toast(text)`, `panel(html, {side})`, `closePanel()` |
| `storage` | `get(key)`, `set(key, value)`, `all()` — per add-on JSON file |
| `net` | `fetch(url, opts)` |
| `rules` | `add(contentRuleListJSON)`, `remove(id)` — extra blocking rules |
| `settings` | `get(key)` — values declared in the add-on's `settings` field |
| `slots` | `provide(name, impl)` — replace a kernel subsystem (`downloads`, `history`, `palette`, `tabstrip`, `newtab`, `suggest`, `search`, `session`) |
| `decide` | `choice(state, options)`, `score(state, rubric)`, `bool(state, question)` → result + `confidence`; pass `{rules, threshold}` |
| `hooks` | `on(name, fn)` — `beforeNavigate({url, tab})` may return `{cancel: true}` or `{redirect: url}`; `beforeDownload({url, filename})` may return `{cancel: true}` or `{path}`; `tabCreated`, `tabLoaded`, `tabClosed`, `message` are observe-only |

## Replacing a subsystem

```js
// downloads go to a dated folder
export default {
  name: "Dated downloads",
  beforeDownload({ filename }) {
    return { path: `~/Downloads/${new Date().toISOString().slice(0, 10)}/${filename}` };
  },
};

// a different search engine, by providing the `search` slot
export default {
  name: "DuckDuckGo",
  setup({ slots }) {
    slots.provide("search", { url: (q) => "https://duckduckgo.com/?q=" + encodeURIComponent(q) });
  },
};
```

Shipped add-ons in `addons/default/` and `addons/optional/` are the reference: copy one to change a default.

## Page API (`page.run` argument)

- `on(event, fn)`: receive `tab.send(event, data)` from the host.
- `emit(event, data)`: send to the host; arrives as `onMessage({ tab, event, data })`.

Page code runs in the add-on's own isolated world: it sees the page's DOM, not the page's JavaScript
variables, and other add-ons cannot see it.

## Globals in the host context

`console.log` (shown in the add-ons page log), `setTimeout`, and standard JavaScript. No `fetch`:
use `ctx.net.fetch`.

## Swift add-on shape

```swift
// Sources/Addons/Indexer.swift
struct Indexer: Addon {
    let id = "indexer"
    let commands: [Command] = [
        Command("indexer.search", title: "Search local files", key: "cmd+shift+f") { ctx in
            // native work here
        }
    ]
    func onTabLoad(_ tab: Tab, ctx: Context) {}
}
```

The same `Context` namespaces as JS, in Swift form. Register in `Addons.all`.

## Rules for add-on authors

- One file per add-on. No imports between add-ons.
- Never touch the core's files.
- Command ids are `<addon-id>.<verb>`.
- Throwing is fine: the host disables the add-on and shows the error. It never crashes the browser.
