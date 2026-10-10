---
name: addon
description: Write, fix or fork a lean browser add-on. Use when the user says "/addon", "add-on for lean", "make the browser do X", "add a command/shortcut to lean", or describes any browser feature they want in lean (reader mode, tab grouping, a site tweak, a different search engine, a palette group). Produces one file in ~/.config/lean/addons/ that hot-reloads into the running browser.
---

# /addon — one feature, one file

lean is a tiny WebKit browser where every feature beyond tabs is an add-on. Your job: turn the user's
request into one add-on file that loads cleanly, without touching the kernel.

## Steps

1. **Read the contract.** `API.md` in the lean repo (`~/Developer/lean/API.md`). It is the whole API;
   anything not there does not exist. Skim the shipped add-ons in `addons/default/` and
   `addons/optional/` for the closest example and copy its patterns.
2. **Fork or new?** If the request changes a shipped add-on (history, session, darkmode, …), copy it
   to `~/.config/lean/addons/<same-id>.js` and edit the copy: same id overrides the shipped one.
   Otherwise write a new file.
3. **JS or Swift?** JS by default. Swift only for native UI, files, Keychain or SQLite. Say why if you
   pick Swift; it needs `./build.sh` and a relaunch.
4. **Write the file** `~/.config/lean/addons/<id>.js` (id = lowercase-with-hyphens; command ids start
   with it). Keep it small: hooks get `(payload, ctx)`; DOM work goes in `page.run`; host has no DOM.
5. **Check it:** `~/Developer/lean/build/lean.app/Contents/MacOS/lean --check ~/.config/lean/addons/<id>.js`.
   Fix until it prints ✔. Never hand over a file that fails the check.
6. **Optional live test** (only if the browser runs with `LEAN_DEV=1`):
   `lean --run <command-id>`, `lean --run key <chord>`, then read `~/.config/lean/dev-state.json`
   (add-on errors and logs are there).
7. **Report** in two lines: what it does, its command name and key. If the API lacked something,
   say exactly what, and do not hack around it in the kernel.

## Don'ts

- Don't edit kernel Swift files to make an add-on work.
- Don't add dependencies or build steps for JS add-ons.
- Don't bind keys that collide with Chrome/Safari defaults unless asked.
