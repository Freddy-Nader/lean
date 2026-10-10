import AppKit

/// Development channel, on only when launched with LEAN_DEV=1.
/// `lean --run <command-id> [arg]` from another shell runs a command in the running app and the app
/// writes its state to ~/.config/lean/dev-state.json, so tests can drive and inspect it.
@MainActor
enum Dev {
    nonisolated static let name = Notification.Name("app.lean.browser.run")
    static var lastEval = ""
    private static var napBlock: NSObjectProtocol?
    static var stateFile: URL { Commands.configDir.appending(path: "dev-state.json") }

    /// Returns true if this process was a `--run` client and should exit.
    nonisolated static func sendIfClient() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--run"), i + 1 < args.count else { return false }
        let payload = args[(i + 1)...].joined(separator: "\u{1f}")
        DistributedNotificationCenter.default().postNotificationName(name, object: payload, deliverImmediately: true)
        return true
    }

    static func listen(_ app: App) {
        guard ProcessInfo.processInfo.environment["LEAN_DEV"] == "1" else { return }
        // App Nap would delay commands sent from a shell while the window is in the background.
        napBlock = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "dev channel")
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { n in
            let parts = (n.object as? String)?.components(separatedBy: "\u{1f}") ?? []
            MainActor.assumeIsolated {
                guard let id = parts.first else { return }
                if id == "load", parts.count > 1 { app.current?.load(parts[1]) }
                else if id == "key", parts.count > 1 { press(parts[1]) }
                else if id == "type", parts.count > 1 { parts[1].forEach { press(String($0)) } }
                else if id == "click", parts.count > 2, let x = Double(parts[1]), let y = Double(parts[2]) { click(x, y) }
                else if id == "snapshot", parts.count > 1 { snapshot(app, parts[1]) }
                else if id == "eval", parts.count > 1, let t = app.current?.tab {
                    t.webView.evaluateJavaScript(parts[1]) { r, e in
                        MainActor.assumeIsolated { lastEval = "\(r ?? e?.localizedDescription ?? "nil")"; dump(app) }
                    }
                } else { Commands.shared.run(id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { dump(app) } }
            }
        }
        dump(app)
    }

    /// Renders the current window's view tree to a PNG (glass and web content may come out flat).
    static func snapshot(_ app: App, _ path: String) {
        guard let v = app.current?.window?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Clicks at (x, y) from the window content's top-left, through NSApp.sendEvent like a real mouse.
    static func click(_ x: Double, _ y: Double) {
        guard let w = App.shared?.current?.window, let v = w.contentView else { return }
        let p = NSPoint(x: x, y: v.bounds.height - y)
        // Tracking areas don't fire for synthetic events, so hover a tab by hand (reveals its ×).
        var hit = v.hitTest(v.convert(p, from: nil))
        while let h = hit, !(h is TabStrip.TabButton) { hit = h.superview }
        if let t = hit as? TabStrip.TabButton,
           let e = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            t.mouseEntered(with: e)
        }
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        // Queue the mouse-up first: an NSButton's mouseDown runs a tracking loop that waits for it.
        if let up = event(.leftMouseUp) { NSApp.postEvent(up, atStart: false) }
        if let down = event(.leftMouseDown) { NSApp.sendEvent(down) }
    }

    /// Synthesizes a real key event ("return", "down", "cmd+k", "a") through NSApp.sendEvent, so it
    /// passes the key map and the focused field exactly like typing does.
    static func press(_ chord: String) {
        guard let key = Key(chord), let w = NSApp.keyWindow ?? App.shared?.current?.window else { return }
        let codes: [String: (UInt16, String)] = ["return": (36, "\r"), "tab": (48, "\t"), "escape": (53, "\u{1b}"),
                                                  "delete": (51, "\u{7f}"), "down": (125, "\u{F701}"), "up": (126, "\u{F700}"),
                                                  "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "space": (49, " ")]
        // ANSI key codes, so characters(byApplyingModifiers:) resolves the same letter.
        let ansi: [Character: UInt16] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24,
            "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
            "k": 40, ",": 43, "n": 45, "m": 46, ".": 47, " ": 49]
        let (code, chars) = codes[key.key] ?? (key.key.first.flatMap { ansi[$0] } ?? 0, key.key)
        let flags = NSEvent.ModifierFlags(rawValue: key.mods)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
                NSApp.sendEvent(e)
            }
        }
    }

    static func dump(_ app: App) {
        let windows = app.windows.map { w in
            [
                "key": w === app.current,
                "active": w.activeIndex,
                "tabs": w.tabs.map { ["title": $0.title, "url": $0.url?.absoluteString ?? ""] },
            ] as [String: Any]
        }
        let keys = Dictionary(uniqueKeysWithValues: Commands.shared.all.keys.map { ($0, Commands.shared.key(for: $0) ?? "") })
        let downloads = Downloads.shared.items.map { ["file": $0.file?.path ?? "", "done": $0.done, "failed": $0.failed] as [String: Any] }
        let state: [String: Any] = ["windows": windows, "commands": keys, "downloads": downloads,
                                    "rules": Rules.shared.active, "eval": lastEval, "palette": Palette.shared.isOpen,
                                    "editing": (app.current?.window?.firstResponder as? NSText).map { "\($0.string) [selected \($0.selectedRange.length)]" } ?? "",
                                    "addons": AddonHost.shared.addons.mapValues { a in
                                        ["loaded": a.isLoaded, "error": a.error ?? "", "commands": a.commandIDs, "logs": a.logs] as [String: Any]
                                    }, "ruleErrors": Rules.shared.errors]
        if let d = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: stateFile)
        }
    }
}
