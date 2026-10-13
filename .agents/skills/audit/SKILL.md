---
name: audit
description: >
  Audit files for overcomplication (code that has a simpler implementation, and code that guards
  against cases that never happen in practice) and for security holes typical of AI-written code.
  Use when the user says "/audit", "audit this", "what's overcomplicated", "what can we cut",
  "find bloat", "is this safe", "security check", or points at files and asks if they can be
  leaner. Read-only by default; fixes only what the user picks.
argument-hint: "[path ...]"
---

# /audit — find what can go, and what can hurt

lean should be as small as possible, still work well, and be safe to browse with. Your job: read
the given files (or the files changed on this branch, or the whole repo if asked) and list every
place that could be smaller without losing behavior anyone relies on, plus every security hole.
lean is vibe-coded: assume nobody reviewed it for security, so check it on every run, not only
when asked.

## Look for three things

**1. A simpler implementation exists.**
- Code that rebuilds what the stdlib, the platform (WebKit, AppKit, Foundation) or a helper already
  in this repo does.
- Abstractions with one user: protocols, wrappers, factories, generic helpers, config objects.
- Indirection that adds nothing: pass-through functions, type conversions back and forth,
  state copied into a second place, enums or options with one live case.
- Long code a shorter, equally clear version replaces.

**2. Assumptions that never happen.**
- Guards, fallbacks, retries and error paths for inputs no caller produces.
- Options, parameters, flags or config keys nothing sets, or always set to the same value.
- Branches for platforms, versions or states the project does not support.
- Dead code: unused functions, exports, files, add-on hooks, CSS, settings.

**3. Security holes.** Trace untrusted input to what it can reach. Untrusted means: web page
content and URLs, add-on files (third-party add-ons exist), downloaded files, network responses,
other local processes, and files other apps write. Check in this order:
- **Web page → native.** Script message handlers, `__lean_dispatch`, add-on JS worlds: can a page
  call into them, spoof an add-on, or read what another add-on or another origin sees? Is anything
  a page sends evaluated, interpolated into JS (`evaluateJavaScript` with string building), or used
  as a file path, URL or shell argument without escaping/validation?
- **Add-on → system.** What `API.md` hands add-ons (`fetch`, files, settings, Swift add-ons):
  arbitrary hosts, `file://`, headers like `Cookie`/`Authorization`, path traversal (`../`) out of
  `~/.config/lean`, anything that runs with no user consent.
- **Updates and downloads.** Is the update manifest itself authenticated (signature or pinned key),
  not just hashed by values it ships? HTTPS only, no redirects to other hosts, atomic replace,
  no ad-hoc re-signing that hides tampering. Downloads keep the quarantine attribute and never
  auto-open.
- **Secrets and personal data.** Imported cookies, history, Keychain items: decrypted copies left
  in temp files, logs, `dev-state.json`, crash output or world-readable files (check permissions
  and cleanup on every error path). No tokens, keys or personal paths committed to the repo.
- **Local channels.** Dev hooks (`LEAN_DEV`, `--run`, distributed notifications), sockets,
  URL schemes: can another local process or a web page trigger them, and do they ship enabled?
- **Process and shell.** `Process`/`/bin/sh` calls built from strings, unquoted paths, `PATH`
  lookups instead of absolute binaries.
- **WebKit config.** File access from file URLs, universal access, disabled TLS checks, mixed
  content, JS on privileged pages (settings, palette) that loads remote content.
- **Classic AI-code slips.** `try?` swallowing a failed integrity/permission check and continuing,
  `!` force-unwraps on untrusted input (crash = DoS), `allowsArbitraryLoads` in `Info.plist`,
  checks done in JS that the native side trusts, TODO-security comments.

Prove each hole: show the path from the untrusted source to the sink with file:line for each hop,
and say who can trigger it (any web page / a malicious add-on / a local process / a network
attacker). If you cannot show the path, mark it *unsure*. Never weaken a security check to save
lines.

Prove each "never happens" claim: grep every caller and every config/add-on that could reach it
(`Sources/`, `addons/`, `config/`, `Tests/`, `API.md`). If you cannot prove it, mark it *unsure*.

## Do not flag

As cuts (1–2): validation at trust boundaries (web content, add-on input, files on disk), error
handling that prevents data loss, security checks, accessibility, anything in `API.md` add-ons
may use, and anything `SPEC.md` asks for. Style nits are not findings.

## Report

Security first, worst first, one line each:

`path:line — hole — who can trigger it — fix — critical|high|medium|low — sure|unsure`

Then cuts, biggest win first:

`path:line — what — simpler version — lines saved — sure|unsure`

If there are no security findings, say so and list the surfaces you checked. End with the total
lines that could go and the one or two findings worth doing first (any critical/high security
hole comes first). Do not edit anything until the user picks findings; then apply them as the
smallest diffs, run `./build.sh` and the tests, and report the results.
