"""Run: python3 -I tests/test_manifest.py"""
import hashlib, importlib.util, json, pathlib, tempfile
spec = importlib.util.spec_from_file_location("manifest", pathlib.Path(__file__).parent.parent / "scripts/manifest.py")
manifest = importlib.util.module_from_spec(spec); spec.loader.exec_module(manifest)

with tempfile.TemporaryDirectory() as t:
    app, out = pathlib.Path(t) / "lean.app", pathlib.Path(t) / "dist"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/MacOS/lean").write_bytes(b"binary")
    for rel, body in {"default/a.js": b"a", "optional/b.js": b"b"}.items():
        (app / "Contents/Resources/addons" / rel).parent.mkdir(parents=True, exist_ok=True)
        (app / "Contents/Resources/addons" / rel).write_bytes(body)
    (app / "Contents/Resources/addons/default/notes.txt").write_bytes(b"ignored")
    m = manifest.build(app, out, "abc123")
    assert m["commit"] == "abc123" and m["binary"] == hashlib.sha256(b"binary").hexdigest()
    assert set(m["files"]) == {"addons/default/a.js", "addons/optional/b.js"}
    assert (out / "addons__default__a.js").read_bytes() == b"a" and (out / "lean").read_bytes() == b"binary"
    assert json.loads((out / "manifest.json").read_text()) == m
print("manifest tests passed")
