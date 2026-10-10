# Build progress

Checkpoint state for resuming an interrupted run. One commit per checkpoint.

| # | Checkpoint | Status |
|---|---|---|
| 0 | Spec, API, research | done `34fa020` |
| 1 | Window, web view, address bar, inspector | done `8c8e4e9` |
| 2 | Command registry, keys.json, find bar, dev channel | done `34d2354` |
| 3 | Tabs + Chrome keys | done `096d4fa` |
| 3b | Downloads + settings.json | done `4fc7f45` |
| 4 | Rule-list engine + EasyList converter | done `b0323b6` |
| 5 | JS add-on host: hot reload, isolation, slots, hooks, lean://addons page | done `c924b31` |
| 6 | Default add-ons (palette, tabstrip, adblock, history, downloads-panel, session, link-copy) + optional darkmode | done |
| 6a | Swift add-on protocol, Rank service, palette, tab strip | done |
| 7 | Import add-on (Chromium history/bookmarks/cookies, Safari history/bookmarks) | done |
| 8 | `/addon` skill + `lean --check` + full API.md | done |
| 9 | Phase 2: Chrome extensions, Web Store, password test | todo (needs manual testing) |

Measured: launch ~170 ms warm (`LEAN_BENCH=1`), binary ~150 KB.
