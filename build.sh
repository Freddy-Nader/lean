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
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --output-format human-readable-text --notices --warnings --errors --output-partial-info-plist /dev/null --app-icon AppIcon --include-all-app-icons --enable-on-demand-resources NO --target-device mac --platform macosx --minimum-deployment-target 15.4 >/dev/null
# A stable identity keeps macOS privacy grants (Full Disk Access) across builds; ad hoc changes
# identity every build. Create it once with scripts/signing-cert.sh.
if security find-certificate -c lean >/dev/null 2>&1; then
  codesign --force --sign lean "$APP"
else
  echo "warning: no 'lean' signing cert (scripts/signing-cert.sh), signing ad hoc" >&2
  codesign --force --sign - "$APP" >/dev/null 2>&1
fi
echo "built $APP"
