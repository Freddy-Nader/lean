# Phase A — glass top bar, zero tabs, palette-first, general settings

Executor brief. Read this file, then each checkpoint spec in order. Read `SPEC.md`, `API.md` and the
code each spec names before editing.

## Goal (user's words, condensed)

1. Liquid Glass look (macOS 26 `NSGlassEffectView`), like Safari/Arc-style dark glass capsules.
2. No tabs open → top bar shows only a `+` at the right; the palette field sits in the middle of the
   window. Typing shows Raycast-style suggestions (the existing ⌘K palette rows). No tab exists until
   the user presses ↵.
3. With ≥1 tab, ⌘T opens the palette; ↵ opens the result in a **new** tab.
4. Tabs are compact (favicon + title). The focused tab is wider, a glass capsule, and shows only the
   host: no `www.`, nothing after the TLD (`https://www.inkandswitch.com/essay/x` → `inkandswitch.com`).
5. The focused tab **is** the address field: ⌘L turns it into an editable field with the full URL.
   There is no separate address field any more.
6. ⌘, opens `lean://settings`: general settings (not only add-ons), add-ons as one section.
7. Everything user-facing must be reachable from the palette by construction: commands (already),
   declared settings (new `Settings.declare`), and add-ons that are switched off ("Turn On Import").

Out of scope (do not build): natural-language argument pills (Phase B), drag-to-reorder, a separate
settings window, URL editing by clicking the tab, restyling left/right/bottom tab positions beyond
what falls out of the shared code.

## Rules

- Lazy senior dev: smallest complete change, reuse what exists, no new dependencies, no
  abstractions nobody asked for. Match surrounding style (terse doc comments, one-line `why`s).
- Swift 6, AppKit. Package min is macOS 15.4: every macOS 26 API behind `if #available(macOS 26, *)`
  with the old `NSVisualEffectView` look as fallback.
- Work on branch `phase-a` (create from `main`). One commit per checkpoint, conventional message,
  ending with `Co-Authored-By: Claude Sonnet <noreply@anthropic.com>`. Never push, never force.
- After each checkpoint: `swift test` passes, `./build.sh` succeeds, then run the app and check it
  (see "Verify" below). Update `docs/phase-a/STATUS.md` (checkpoint, commit, what you verified,
  open issues). Then stop and report back; the orchestrator reviews before the next checkpoint.
- Do not revert unrelated changes. Do not touch `~/.config/lean/` except via the running app.

## Verify (how to see the app)

Shell screen capture is blocked (no screen-recording permission). Checkpoint 1 adds a dev-only
`snapshot` command, so you can see the UI from the shell:

```
pkill -x lean; ./build.sh && open --env LEAN_DEV=1 build/lean.app
build/lean.app/Contents/MacOS/lean --run snapshot /tmp/lean-shot.png   # then Read the PNG
build/lean.app/Contents/MacOS/lean --run key cmd+t                     # if Dev supports keys; see Dev.swift
build/lean.app/Contents/MacOS/lean --run load example.com
cat ~/.config/lean/dev-state.json
```

Read `Sources/LeanKit/Dev.swift` and `README.md` for the exact dev-channel syntax before using it.
The snapshot renders the window's view tree (`cacheDisplay`); glass and web content may render flat
or blank there. That is fine for layout checks. The orchestrator does the final real-pixel check.

## Measured facts (this machine, macOS 26.3)

- Window style `.titled .fullSizeContentView`, transparent titlebar, no toolbar: titlebar inset 32pt,
  traffic-light centre 16pt from top, zoom button right edge x=69.
- Same with `NSToolbar` + `.unifiedCompact`: inset 40pt, centre 20pt, zoom right edge x=72. Content
  views under a toolbar may stop receiving clicks; prefer **no toolbar**.

## Checkpoints

| # | Spec | Summary |
|---|---|---|
| 1 | `01-zero-tabs-palette.md` | optional active tab, zero-tab window, palette prompt hook, ⌘T, snapshot dev command, session.js |
| 2 | `02-settings.md` | `Settings.declare`, `lean://settings` page, ⌘,, palette settings + switched-off add-ons, JS `settings.declare` |
| 3 | `03-top-bar-tabs-glass.md` | glass helper, top bar row with nav buttons, compact tabs with favicons, focused tab shows host, palette glass |
| 4 | `04-address-in-tab.md` | remove address field, ⌘L edits focused tab, ↓ opens palette, docs + PROGRESS.md |
