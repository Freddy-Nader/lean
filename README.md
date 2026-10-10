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

Every action is a command. Override keys in `~/.config/lean/keys.json` (reloads on save):

```json
{ "cmd+e": "address.focus", "cmd+l": null }
```

`null` unbinds a default.

## Drive the app from a shell (development)

```sh
open --env LEAN_DEV=1 build/lean.app
build/lean.app/Contents/MacOS/lean --run page.reload       # run any command id
build/lean.app/Contents/MacOS/lean --run load github.com   # load an address
cat ~/.config/lean/dev-state.json                          # windows, tabs, commands + keys
```

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
