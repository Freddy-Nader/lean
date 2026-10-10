# lean — spec

Status: draft v2 for review (2026-10-10). Nothing built yet.

## Goal

A macOS browser that feels instant, stays tiny, and that anyone can reshape to fit their needs by writing (or asking an AI for) add-ons.

Success criteria:
- Cold launch < 300 ms and idle RAM close to Safari.
- Kernel under ~2k lines of Swift.
- A new add-on goes from prompt to working in under a minute, without restarting the app.
- Every default feature can be read, copied, or replaced by a user add-on.

## Non-goals

- Cross-platform. macOS only.
- Shipping Chromium. The engine is WebKit (`WKWebView`), which ships with macOS.
- Sync, accounts, profiles, built-in AI. Add-ons can add these later.
- Our own password manager. Passwords stay in Apple Passwords.

## Stack

- Swift 6, AppKit for windows and the tab strip, SwiftUI only where it is clearly shorter (palette, settings).
- SwiftPM (`Package.swift`) + `build.sh` that assembles an ad-hoc-signed `lean.app`. No Xcode project.
- No third-party dependencies (system `sqlite3` and `CommonCrypto` are fine).
- Minimum macOS 15.4 (needed for `WKWebExtension`); developed on macOS 26.

Rejected: Chromium/CEF (heavy, what Rauch's Mini uses), Electron, Rust or Zig cores (with WebKit doing the heavy work there is nothing left for them to do, and bridging to AppKit adds code).

## Architecture: kernel + slots + add-ons

Three layers. This is what makes it hackable.

1. **Kernel** (cannot be replaced, kept tiny): windows, the tab model, `WKWebView` setup, the command registry, the key map, content rule lists, settings storage, and the add-on host.
2. **Slots**: each subsystem the kernel needs is a named slot with one provider. Defaults ship in the box; an add-on can `provide()` a slot to replace the default completely.

   | Slot | Default provider |
   |---|---|
   | `downloads` | save to the downloads folder, simple list panel |
   | `history` | SQLite history, feeds the palette |
   | `palette` | Notion-style grouped palette (below) |
   | `tabstrip` | native strip with position setting |
   | `newtab` | blank page with palette open |
   | `suggest` | address-bar suggestions (tabs, history, search) |
   | `search` | search engine URL template |
   | `session` | restore tabs on launch |

   The add-ons page shows each slot and who provides it, and lets the user pick when two add-ons want the same slot.
3. **Hooks**: events add-ons can observe or intercept without replacing a whole slot: `beforeNavigate` (cancel/redirect), `beforeDownload` (take over), `tabCreated`, `tabLoaded`, `tabClosed`, `keyDown`.

**Default and optional add-ons use the same format as user add-ons** and live in `addons/default/` and `addons/optional/`. Every default (dark mode, history, downloads panel, import) is a working example someone can open, copy, and change. That's the "anyone can customize it" path: fork a built-in, don't learn a framework.

## Kernel features

1. Windows and tabs: new, close, switch, reorder, reopen closed (⌘⇧T), ⌘1–9.
2. Back, forward, reload, stop, find in page, zoom.
3. Downloads via `WKDownload`. Default folder `~/Downloads`, changeable in settings (`downloads.folder`).
4. Rule-list engine: compiles and applies `WKContentRuleList`s that add-ons hand it, with per-site pause. The `adblock` default add-on supplies EasyList + EasyPrivacy, converted at build time and split under the 150k-rule limit.
5. Commands: every action, kernel or add-on, is a named command (`tab.new`, `darkmode.toggle`).
6. Keybindings: `~/.config/lean/keys.json` maps a key to a command id. Defaults match Chrome/Safari. Reloads on save.
7. Developer tools: `WKWebView.isInspectable = true`, so Safari's Web Inspector opens with ⌘⌥I and from right-click → Inspect Element.

## Three tiers: what ships where

Rule: the kernel holds only what every user needs to browse. If one person would miss it and another wouldn't, it is an add-on from day one, even if the author uses it daily.

| Tier | Contents | Who gets it |
|---|---|---|
| **Kernel** (Swift, not replaceable) | windows, tab model, web view, navigation, find, zoom, `WKDownload` to a folder, inspector flag, command registry, key map, rule-list engine, settings, add-on host | everyone, always |
| **Default add-ons** (on at first launch, can be disabled or replaced) | `palette`, `tabstrip` (with position setting), `adblock` (EasyList + EasyPrivacy lists fed to the kernel engine), `history`, `downloads-panel`, `session`, `link-copy` (⌘⇧C) | everyone, but removable |
| **Optional add-ons** (ship in `addons/optional/`, off until enabled) | `darkmode` (⌥N), `import`, `chrome-extensions`, `webstore` | whoever wants them; your own setup turns them on |

`palette` and `tabstrip` are Swift add-ons (native UI, must feel instant); the rest of the defaults are JS. The add-ons page and settings stay in the kernel, so you can always turn add-ons back on.

So the bare browser with every add-on disabled is: one window, tabs switchable only by keys, an address bar, and nothing else. That is the minimal baseline we measure launch time and memory against.

## Palette (default add-on, ⌘K)

Combines Notion's grouped results with Raycast's interaction model.

**From Notion:** one search field, grouped results under small section headers.

- Groups, in order: **Tabs** (URL as grey subtitle) → **Commands** → **Settings** → add-on groups (history, bookmarks) → **Search the web for "…"** as the fallback.
- Typing filters every group at once; empty groups hide.

**From Raycast:**

- **Right-side accessory** on each row: the item type (Tab, Command, Setting) or its shortcut, so you learn keys by using the palette.
- **Action bar at the bottom:** the primary action with ↵ on the left, `Actions ⌘K` on the right.
- **Action panel:** pressing ⌘K again on a selected row opens that item's secondary actions. For a tab: close, copy link, move to new window, mute, reload. Add-ons can add actions to any item type.
- **Push navigation:** some rows open a sub-list in place (Settings → Downloads folder, Add-ons → one add-on's commands). Esc goes back one level, Esc at the root closes.
- **Inline arguments:** commands can declare arguments that appear as pills in the search bar (`Search GitHub [query]`), filled with ⇥.
- **Aliases and per-command hotkeys:** assignable from the action panel, written to `keys.json`.
- **Ranking:** frequency and recency of what you pick, so your common choices rise.

**⌘T** opens a new tab with the address field focused and suggestions underneath. **↓** expands it into the full palette.

## Arguments and natural language, without AI

Raycast-style argument pills, filled automatically from plain typing. Deterministic, built from what macOS ships; no model.

- **Command grammars.** Each command declares patterns with typed slots, e.g. `search {site:site} for {query:text}`, `{query:text} on {site:site}`, `open {tab:tab}`, `downloads from {date:date}`.
- **Slot types and resolvers:**
  - `site`: aliases from add-ons and settings (`yt`, `gh`, `wiki`), plus any domain typed.
  - `date`, `url`, `phone`, `address`: `NSDataDetector` ("next friday", "tomorrow 5pm").
  - `tab`, `setting`, `command`: fuzzy match against live lists.
  - `text`: whatever is left.
- **Matching.** Every grammar is tried against the input; candidates are scored by how much of the input the slots explain plus frecency (below). The top parse fills the pills; ⇥ moves between pills; the user can correct one pill without retyping the rest.
- **Examples.** `yt lofi beats` → YouTube search, `query=lofi beats`. `gh swift browser` → GitHub search. `history from last tuesday` → history filtered by date. `close tabs from youtube` → tab command with `site=youtube.com`.
- **NaturalLanguage framework** (`NLTagger`: lemmas, language detection) normalises words so "searching" and "search" hit the same grammar. Classical on-device NLP, not generative AI.
- **Kernel or add-on.** The parser and the grammar registry are kernel (small, pure, unit-tested); grammars come from add-ons.

## Suggestions and recent searches, done smartly

Not a reverse-chronological list. Owned by a kernel ranking service (`rank`), so every palette and address-bar provider shares one tuned algorithm; history data comes from the `history` add-on.

- **Frecency score**, Firefox-style: each visit or pick adds weight that decays over time (half-life ~ 30 days); typed visits weigh more than link clicks.
- **Dedupe by meaning**: normalise case, whitespace, tracking params (`utm_*`, `fbclid`), and `www.`; merge a search query with the result page you ended up on.
- **Reformulation pruning**: if a search is replaced by a refined one within ~60 s, the abandoned one is down-weighted, so typos and dead ends stop resurfacing.
- **Context boosts**: items from the current site, items you pick at this time of day, items that are already open tabs (shown as "switch to tab" instead of a duplicate).
- **Prefix and fuzzy match** on title, URL and query; exact-prefix wins ties.
- **Forget**: ⇧⌫ on any suggestion removes it and blocks it from returning.
- **Tuning loop**: picks are logged locally (position chosen, score) so the weights can be adjusted over time with evidence. This is the part meant to be refined in the core over time.

## Decisions: `decide` (typed, Jev-style)

Many small choices inside the browser are decisions, not text generation: pick one option, give a score, answer yes/no. The kernel exposes one tiny interface for them; who answers is pluggable.

```
decide.choice(state, options)  -> { pick, confidence }
decide.score(state, rubric)    -> { score, confidence }
decide.bool(state, question)   -> { value, confidence }
```

- **Providers** (slot `decider`, chain in order, first confident answer wins):
  1. rules written by the calling add-on (always present, deterministic);
  2. Apple Foundation Models with a fixed answer list (built in, optional add-on);
  3. a small local Jev-style model (optional add-on): first candidate Laya via ONNX (~650 MB, Apache 2.0), alternative Kev 0.8B via MLX; see `docs/research/local-models.md` §5;
  4. TypeSafe's hosted Jev (optional add-on, opt-in, sends data off device).
- **Every call has a deterministic fallback and a confidence threshold.** Below the threshold the browser asks or does nothing; it never guesses silently on something destructive.
- **Corrections are logged locally**, so each decision gets better with evidence and can later fine-tune a local model.
- With no provider add-on installed, `decide` is just the rules: the bare browser stays model-free.

Candidate uses, roughly by value:

| Use | Type | Effect |
|---|---|---|
| Palette: which command did you mean | choice | fills argument pills when the grammar parser is unsure |
| Address bar: URL, search, or command | choice | replaces brittle heuristics |
| Prefetch the link you'll likely click next | score | pre-loads it, so pages feel instant |
| Cookie banners: which button is "reject all" | choice | auto-declines consent |
| Popups: newsletter / paywall nag / ad overlay | bool | hides annoyances that filter lists miss |
| Downloads: which folder (invoices, papers, installers) | choice | auto-filing |
| Permission requests (notifications, location) | bool | auto-deny the spammy ones |
| Stale tabs: reading / reference / done | choice | suggests closing or archiving |
| Tab grouping by topic | choice | groups without manual work |
| Is this page an article / already dark | bool | auto reader mode, smarter darkmode |
| Is this worth remembering | score | weights history and suggestion ranking |
| Save to a notes folder | bool | suggests clipping pages worth keeping |

## Later: local models (research)

Exploration track, not v1. Any model feature is an optional add-on so the bare browser stays model-free. Findings: `docs/research/local-models.md`.

## Default keys (additions to Chrome/Safari defaults)

| Key | Command | Provided by |
|---|---|---|
| ⌘K | `palette.open` | palette add-on |
| ⌘L | `address.focus` (shows the full link, selected) | kernel |
| ⌘⇧C | `link.copy` (copies current URL, toast confirms) | link-copy add-on |
| ⌘⌥I | `devtools.toggle` | kernel |
| ⌥N | `darkmode.toggle` | darkmode add-on (optional) |

## Optional add-on: darkmode

⌥N, like Comet. First switches the page to dark appearance so sites with a real dark mode use it; if the page stays light, applies a CSS inversion that re-inverts images and video. Remembered per site, plus a global "dark everywhere" setting. Injected at document start so there is no white flash.

## Optional add-on: import from other browsers (Swift)

Supported sources: Chromium browsers (Arc, Brave, Chrome, Comet, Dia, Edge, Vivaldi; same file formats) and Safari.

| Item | Chromium browsers | Safari |
|---|---|---|
| Bookmarks | `Bookmarks` JSON | `Bookmarks.plist` (needs Full Disk Access) |
| History | `History` SQLite | `History.db` (needs Full Disk Access) |
| Logged-in sessions (cookies) | `Cookies` SQLite, decrypted with the browser's Keychain key (macOS asks once) | `Cookies.binarycookies` |
| Search engine, homepage | `Preferences` JSON | plist |
| Site permissions (location, camera) | `Preferences` JSON | skip |
| Passwords | not imported: stay in Apple Passwords |
| Profiles | v1 imports one chosen profile |

Cookies go into `WKHTTPCookieStore`, so you stay logged in to sites after import.

## Optional add-ons: chrome-extensions + webstore (Swift, phase 2)

- Runtime: `WKWebExtensionController` attached through a kernel hook on web view configuration. Runs Safari-compatible MV3 extensions (uBlock Origin Lite, 1Password, Bitwarden, Dark Reader all have Safari builds).
- Store install: paste a Chrome Web Store URL → download CRX → verify CRX3 signature → unpack → load.
- Chrome-only APIs that WebKit lacks are not shimmed in v1. Search ships ~266 KB of shims for this; we add shims only for extensions people actually use.

## Add-ons

Two kinds, one shared API (see `API.md`).

- **JS add-ons (default).** One file: `~/.config/lean/addons/<id>.js`.
  - Host half runs in a `JSContext` (JavaScriptCore), one per add-on.
  - Page half is injected as a `WKUserScript` into an isolated `WKContentWorld`.
  - Hot reload: on save, the host unloads the old version and loads the new one; tabs stay open.
  - Any thrown error disables that add-on and shows a badge; the browser keeps running.
- **Swift add-ons (native/heavy work).** One file: `Sources/Addons/<Id>.swift`, conforming to `Addon`, listed in `Addons.all`. Needs `swift build` (seconds). Use for file system, Keychain, SQLite, native UI, local models.
- Rust or Zig add-ons: possible later via WebAssembly loaded from a JS add-on. Not in v1.
- Sharing: an add-on is one file, so sharing is sending the file. Add-ons have full power over the browser; installing one from someone else means trusting it.

## The `/addon` skill

Lives at `.agents/skills/addon/SKILL.md` (symlinked into `.claude/skills/`).

1. Read `API.md` and the built-in add-ons as examples.
2. Decide JS or Swift (Swift only when native access is needed; say why).
3. Write the file.
4. Run `lean check <file>`: loads the add-on headlessly and reports errors.
5. Hot reload picks it up; report the command name and default key.

## Open items

- Password autofill: test whether Apple's "iCloud Passwords" extension runs under `WKWebExtension` in a third-party app. Fallback: copy-paste from Passwords.app.
- ⌥N fires before the page sees the key. On layouts where ⌥N is a dead key (US: ⌥N then N types ñ), users may want to rebind it in keys.json.
- YouTube in-video ads need a page-script add-on, not network rules.
- Name `lean` is a placeholder.

## Build order (checkpoints)

1. Window + one `WKWebView` + address bar + inspector. Verify: loads a page; cold launch measured.
2. Tabs + kernel default keys (⌘L, ⌘T, ⌘W, ⌘1–9).
3. Command registry + `keys.json`.
4. Rule-list engine + EasyList build script.
5. Add-on host: JS + hot reload + error isolation + slots + hooks + add-ons page. Verify: an add-on that throws is disabled and the app survives; an add-on replaces `downloads`.
6. Default add-ons: palette, tabstrip, adblock, history, downloads-panel, session, link-copy. Then optional: darkmode. Verify: with all add-ons disabled the browser still opens pages; measure launch + RAM there.
7. Swift `Addon` protocol + import add-on (Chromium first, then Safari).
8. `/addon` skill + `lean check`.
9. Phase 2: Chrome extensions + Web Store install; password test.
