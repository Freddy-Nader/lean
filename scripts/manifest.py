#!/usr/bin/env python3
"""Write the auto-updater's release assets for a built app.

Usage: scripts/manifest.py build/lean.app dist

Writes to dist/: the binary (`lean`), every add-on file under its flattened name
(addons/default/x.js -> addons__default__x.js), and manifest.json, which lists the commit, the
SHA-256 of the binary and the SHA-256 of each add-on file. The app downloads only what differs.
"""
import hashlib, json, shutil, sys
from pathlib import Path

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def flat(rel): return rel.replace("/", "__")

def build(app, out, commit):
    app, out = Path(app), Path(out)
    out.mkdir(parents=True, exist_ok=True)
    exe = app / "Contents/MacOS/lean"
    shutil.copy2(exe, out / "lean")
    res = app / "Contents/Resources"
    files = {}
    for f in sorted(res.glob("addons/*/*.js")):
        rel = f.relative_to(res).as_posix()
        files[rel] = sha(f)
        shutil.copy2(f, out / flat(rel))
    manifest = {"commit": commit, "binary": sha(exe), "files": files}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest

if __name__ == "__main__":
    import plistlib
    app = Path(sys.argv[1])
    commit = plistlib.loads((app / "Contents/Info.plist").read_bytes())["LeanCommit"]
    m = build(app, sys.argv[2], commit)
    print(f"manifest for {commit[:7]}: {len(m['files'])} add-on files")
