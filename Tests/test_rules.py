"""Run: python3 -I tests/test_rules.py"""
import importlib.util, pathlib, re
spec = importlib.util.spec_from_file_location("rules", pathlib.Path(__file__).parent.parent / "scripts/rules.py")
rules = importlib.util.module_from_spec(spec); spec.loader.exec_module(rules)

rx = rules.pattern_to_regex("||ads.example.com^")
assert re.search(rx, "https://ads.example.com/x.js") and re.search(rx, "https://cdn.ads.example.com/x")
assert not re.search(rx, "https://notads.example.com.evil/x")
assert rules.pattern_to_regex("/(a|b)/") is None, "raw regexes skipped"
s = {"skipped": 0}
r = rules.convert_network("||t.com^$third-party,script,domain=a.com|b.com", s)
assert r["trigger"]["load-type"] == ["third-party"] and r["trigger"]["resource-type"] == ["script"]
assert r["trigger"]["if-domain"] == ["*a.com", "*b.com"]
assert rules.convert_network("||t.com^$popup", s) is None and s["skipped"] == 1
assert rules.convert_network("@@||ok.com^", s)["action"]["type"] == "ignore-previous-rules"
blocks, css, allows = rules.convert("example.com##.ad\n##.banner\n||x.com^\n@@||y.com^", {"skipped": 0})
assert len(blocks) == 1 and len(allows) == 1 and css[0]["action"]["selector"] == ".banner"
print("rules tests passed")
