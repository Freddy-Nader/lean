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
