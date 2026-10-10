# lean add-on API (draft)

The only contract add-ons, and the AI writing them, rely on. Anything not here does not exist.

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

  // runs in the host JSContext
  onTabLoad(tab) {},
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
| `hooks` | `on(name, fn)` — `beforeNavigate` and `beforeDownload` may return `{cancel}` or `{redirect}` / `{handled}`; others are observe-only |

## Replacing a subsystem

```js
// downloads go to a dated folder and open in Finder instead of the default panel
export default {
  id: "dated-downloads",
  setup({ slots, hooks }) {
    hooks.on("beforeDownload", (dl) => {
      dl.saveTo(`~/Downloads/${new Date().toISOString().slice(0, 10)}/${dl.filename}`);
      return { handled: true };
    });
  },
};
```

Shipped add-ons in `addons/default/` and `addons/optional/` are the reference: copy one to change a default.

## Page API (`page.run` argument)

- `on(event, fn)`: receive `tab.send(event, data)` from the host.
- `emit(event, data)`: send to the host (`onMessage` handler).

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
