#!/bin/sh
# Builds build/lean.app (ad-hoc signed). Usage: ./build.sh [debug|release]
set -e
cd "$(dirname "$0")"
CONFIG="${1:-release}"
swift build -c "$CONFIG"
APP=build/lean.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Lean" "$APP/Contents/MacOS/lean"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace LeanCommit -string "${LEAN_COMMIT:-dev}" "$APP/Contents/Info.plist"   # CI sets it; "dev" builds never self-update
[ -d Resources/rules ] || python3 -I scripts/rules.py Resources/rules
cp -Rp Resources/rules "$APP/Contents/Resources/"   # -p keeps mtimes, so WebKit's compiled-list cache stays valid
[ -d addons ] && cp -R addons "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "built $APP"
