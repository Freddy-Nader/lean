#!/usr/bin/env python3
"""Convert EasyList-format filter lists to WebKit content-blocker JSON.

Usage: scripts/rules.py [out_dir]   (default: Resources/rules)

Downloads EasyList + EasyPrivacy, converts the subset WebKit can express, and writes
<name>-<n>.json files of at most 50k rules each (WebKit's limit is 150k per list; smaller lists
compile faster and in parallel). Unsupported rules are skipped and counted, never guessed.
"""
import json, re, sys, urllib.request
from pathlib import Path

LISTS = {
    "easylist": "https://easylist.to/easylist/easylist.txt",
    "easyprivacy": "https://easylist.to/easylist/easyprivacy.txt",
}
CHUNK = 50_000
CSS_BATCH = 50  # generic hiding selectors joined per rule

TYPES = {
    "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
    "media": "media", "xmlhttprequest": "fetch", "subdocument": "document", "other": "raw",
    "ping": "ping", "websocket": "websocket",
}
IGNORED_OPTS = {"match-case", "~match-case", "all", "first-party", "~third-party", "1p", "3p", "third-party", "domain"}
UNSUPPORTED_OPTS = {"popup", "csp", "redirect", "redirect-rule", "rewrite", "removeparam", "header", "genericblock",
                    "generichide", "elemhide", "document", "badfilter", "important", "webrtc", "permissions", "replace",
                    "denyallow", "to", "from", "method", "ehide", "ghide", "shide", "specifichide", "cname"}


def pattern_to_regex(p):
    """ABP URL pattern → WebKit url-filter regex (no alternation, no quantifier braces)."""
    if p.startswith("/") and p.endswith("/") and len(p) > 2:
        return None  # raw regexes often use syntax WebKit rejects
    if not p.isascii():
        return None
    start = ""
    if p.startswith("||"):
        p, start = p[2:], r"^[^:]+://+([^:/]+\.)?"
    elif p.startswith("|"):
        p, start = p[1:], "^"
    end = ""
    if p.endswith("|"):
        p, end = p[:-1], "$"
    out = []
    for ch in p:
        if ch == "*":
            out.append(".*")
        elif ch == "^":
            out.append("[/:?=&]")  # separator; WebKit has no end-of-string alternative here
        elif ch in ".+?$(){}[]\\|":
            out.append("\\" + ch)
        else:
            out.append(ch)
    body = "".join(out)
    rx = start + body + end
    if not body.strip(".*") or len(rx) > 300:
        return None
    return rx


def domains(spec):
    inc, exc = [], []
    for d in spec.split("|"):
        d = d.strip().lower()
        if not d or not d.isascii() or "*" in d:
            continue
        (exc if d.startswith("~") else inc).append("*" + d.lstrip("~"))
    return inc, exc


def convert_network(line, stats):
    allow = line.startswith("@@")
    if allow:
        line = line[2:]
    pattern, _, opts = line.partition("$") if "$" in line and not line.startswith("/") else (line, "", "")
    trigger, types = {}, []
    for o in filter(None, opts.split(",")):
        name, _, val = o.partition("=")
        neg = name.startswith("~")
        key = name.lstrip("~")
        if key in UNSUPPORTED_OPTS:
            stats["skipped"] += 1
            return None
        if key == "third-party" or key == "3p":
            trigger["load-type"] = ["first-party" if neg else "third-party"]
        elif key == "domain":
            inc, exc = domains(val)
            if inc and exc:
                stats["skipped"] += 1
                return None
            if inc:
                trigger["if-domain"] = inc
            if exc:
                trigger["unless-domain"] = exc
        elif key in TYPES:
            if neg:
                stats["skipped"] += 1
                return None
            types.append(TYPES[key])
        elif key not in IGNORED_OPTS:
            stats["skipped"] += 1
            return None
    rx = pattern_to_regex(pattern or "*")
    if rx is None:
        stats["skipped"] += 1
        return None
    trigger = {"url-filter": rx, **trigger}
    if types:
        trigger["resource-type"] = sorted(set(types))
    return {"trigger": trigger, "action": {"type": "ignore-previous-rules" if allow else "block"}}


def convert(text, stats):
    blocks, allows, generic_css, specific_css = [], [], [], []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("!") or line.startswith("["):
            continue
        if "#@#" in line or "#?#" in line or "#$#" in line or "#%#" in line or "$$" in line:
            stats["skipped"] += 1
            continue
        if "##" in line:
            doms, _, sel = line.partition("##")
            if not sel.isascii() or ":-abp-" in sel or ":has-text" in sel or ":xpath" in sel or ":upward" in sel:
                stats["skipped"] += 1
                continue
            if doms:
                inc, exc = domains(doms.replace(",", "|"))
                if not inc or exc:
                    stats["skipped"] += 1
                    continue
                specific_css.append({"trigger": {"url-filter": ".*", "if-domain": inc},
                                     "action": {"type": "css-display-none", "selector": sel}})
            else:
                generic_css.append(sel)
            continue
        rule = convert_network(line, stats)
        if rule:
            (allows if rule["action"]["type"] == "ignore-previous-rules" else blocks).append(rule)
    css = [{"trigger": {"url-filter": ".*"}, "action": {"type": "css-display-none", "selector": ", ".join(generic_css[i:i + CSS_BATCH])}}
           for i in range(0, len(generic_css), CSS_BATCH)]
    stats["converted"] = len(blocks) + len(allows) + len(generic_css) + len(specific_css)
    return blocks, css + specific_css, allows


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "Resources/rules")
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.json"):
        old.unlink()
    for name, url in LISTS.items():
        req = urllib.request.Request(url, headers={"User-Agent": "lean-rules/1"})
        text = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
        stats = {"skipped": 0}
        blocks, css, allows = convert(text, stats)
        # Exceptions must come after the rules they cancel, so each chunk carries all exceptions.
        body = blocks + css
        step = CHUNK - len(allows)
        for n, i in enumerate(range(0, len(body), step)):
            rules = body[i:i + step] + allows
            (out / f"{name}-{n}.json").write_text(json.dumps(rules, separators=(",", ":")))
        print(f"{name}: {stats['converted']} converted, {stats['skipped']} skipped")


if __name__ == "__main__":
    main()
