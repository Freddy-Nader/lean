# lean

A minimal macOS browser on WebKit. Spec: [SPEC.md](SPEC.md). Add-on API: [API.md](API.md).

## Build and run

```sh
./build.sh            # release build → build/lean.app
open build/lean.app   # or: open build/lean.app --args https://example.com
swift test            # unit tests
```

Needs Xcode (Swift 6) and macOS 15.4+.

## Measure launch time

```sh
LEAN_BENCH=1 build/lean.app/Contents/MacOS/lean   # prints launch_ms and quits
```

## Keybindings

⌘T opens the palette (↵ opens a new tab), ⌘L edits the focused tab as an address field, ⌘, opens `lean://settings`, ⌘K opens the palette on the current tab.

Every action is a command. Override keys in `~/.config/lean/keys.json` (reloads on save):

```json
{ "cmd+e": "address.focus", "cmd+l": null }
```

`null` unbinds a default.

## Drive the app from a shell (development)

```sh
open --env LEAN_DEV=1 --env LEAN_CONFIG_DIR=/tmp/lean-home/config build/lean.app   # LEAN_CONFIG_DIR: throwaway config dir
build/lean.app/Contents/MacOS/lean --run page.reload       # run any command id
build/lean.app/Contents/MacOS/lean --run load github.com   # load an address
cat ~/.config/lean/dev-state.json                          # windows, tabs, commands + keys
build/lean.app/Contents/MacOS/lean --run click 300 16       # click at x y (points from the window's top-left)
build/lean.app/Contents/MacOS/lean --run snapshot /tmp/s.png   # PNG of the window's view tree (glass may render flat)
```

## Auto-update

A default add-on (`updater`; switch it off on lean://addons). It follows GitHub: every push to
master is built by CI (.github/workflows/release.yml) and published as the rolling release `latest`
with a manifest of hashes. Every 6 hours (and on "Check for Updates" in the palette) lean
downloads only what differs:

- changed add-on files go to ~/.config/lean/updates/ and hot-reload, no restart;
- a changed binary replaces Contents/MacOS/lean, the app is re-signed (with the "lean" cert if the
  keychain has it, else ad hoc), and the new
  build runs at the next launch ("Restart to Finish Update" in the palette does it now).
  The previous binary is kept at ~/.config/lean/updates/lean.prev.

Signing: an ad-hoc signature changes the app's identity every build, so macOS drops privacy grants
(Full Disk Access, needed for Safari import). Run `scripts/signing-cert.sh` once per Mac: it makes a
self-signed "lean" cert in the login keychain that `build.sh` and the updater sign with (click
"Always Allow" on the first keychain prompt). For CI, add two repo secrets (Settings → Secrets →
Actions): `LEAN_P12` = output of `base64 -i ~/.config/lean/signing/lean.p12`, and
`LEAN_P12_PASSWORD` = contents of `~/.config/lean/signing/p12-password`. Grant Full Disk Access
once more after switching to the cert; it then sticks.

Local builds (`./build.sh`) are stamped "dev" and never update themselves. Only builds made by CI
(or with `LEAN_COMMIT=<sha> ./build.sh`) do. To get a self-updating install, once:

    curl -L https://github.com/Freddy-Nader/lean/releases/download/latest/lean.app.zip -o /tmp/lean.zip
    ditto -x -k /tmp/lean.zip ~/Applications

(curl adds no quarantine flag, so Gatekeeper stays quiet.) Rules lists (EasyList) are not part of
updates; they ship in the app. Test it without GitHub: `python3 scripts/manifest.py build/lean.app dist`,
serve `dist/` with `python3 -m http.server`, and launch with `LEAN_UPDATE_URL=http://127.0.0.1:8000`.

## Settings

`~/.config/lean/settings.json` (reloads on save). Defaults:

```json
{ "downloads.folder": "~/Downloads", "search.template": "https://www.google.com/search?q=%s" }
```

## Ad blocking

`scripts/rules.py` downloads EasyList + EasyPrivacy and converts them to WebKit content-blocker JSON
in `Resources/rules/` (gitignored; `build.sh` runs it when the folder is missing). Delete the folder and
rebuild to refresh the lists. First launch compiles them in ~5 s in the background; later launches use
WebKit's cache. Pause on a site with the `rules.togglePause` command.

```sh
python3 -I tests/test_rules.py   # converter tests
```

## Testing keyboard flows

With `LEAN_DEV=1`, `lean --run key cmd+k`, `lean --run type "new tab"` and `lean --run key return`
synthesize real key events (through the key map and focused field), so whole flows can be scripted.

## Writing add-ons

See [API.md](API.md). Check a file before using it:

```sh
build/lean.app/Contents/MacOS/lean --check ~/.config/lean/addons/my-addon.js
```

With Claude Code in this repo, `/addon <what you want>` writes one for you
(`.agents/skills/addon/SKILL.md`).
