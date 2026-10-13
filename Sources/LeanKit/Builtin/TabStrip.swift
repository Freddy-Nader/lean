import AppKit

/// Tab strip (default add-on, provides the `tabstrip` slot). Position is the `tabstrip.position`
/// setting: top, bottom, left, right or hidden. Click selects, middle-click or × closes.
@MainActor
final class TabStrip: SwiftAddon {
    static let shared = TabStrip()
    let id = "tabstrip", name = "Tab Strip", kind = JSAddon.Kind.default
    let summary = "Tabs along an edge of the window. Position: top, bottom, left, right or hidden."

    private var strips: [ObjectIdentifier: Strip] = [:]
    private var observers: [NSObjectProtocol] = []

    var position: String {
        get { Settings.shared.string("tabstrip.position").isEmpty ? "top" : Settings.shared.string("tabstrip.position") }
        set { Settings.shared.set("tabstrip.position", newValue) }
    }

    func load() throws {
        Slots.shared.provideNative("tabstrip", owner: id)
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: BrowserWindow.opened, object: nil, queue: .main) { n in
                let w = n.object as? BrowserWindow
                MainActor.assumeIsolated { if let w { self.attach(w) } }
            },
            nc.addObserver(forName: Settings.changed, object: nil, queue: .main) { n in
                let key = n.object as? String
                MainActor.assumeIsolated { if key == nil || key == "tabstrip.position" { App.shared?.windows.forEach(self.attach) } }
            },
            nc.addObserver(forName: BrowserWindow.tabsChanged, object: nil, queue: .main) { n in
                let w = n.object as? BrowserWindow
                MainActor.assumeIsolated { if let w { self.strips[ObjectIdentifier(w)]?.setNeedsRender() } }
            },
        ]
        App.shared?.windows.forEach(attach)
        BrowserWindow.editAddress = { [weak self] w in self?.strips[ObjectIdentifier(w)]?.edit() ?? false }
        Settings.shared.declare("tabstrip.position", "Tab Position", icon: "rectangle.split.3x1",
                                options: ["top", "bottom", "left", "right", "hidden"].map { ($0.capitalized, $0) }, owner: id)
        for (cmd, title, pos) in [("tabstrip.top", "Tabs on Top", "top"), ("tabstrip.left", "Tabs on Left", "left"),
                                  ("tabstrip.bottom", "Tabs on Bottom", "bottom"), ("tabstrip.right", "Tabs on Right", "right"),
                                  ("tabstrip.hide", "Hide Tab Strip", "hidden")] {
            Commands.shared.register(cmd, title, owner: id) { [weak self] in self?.position = pos }
        }
    }

    func unload() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        App.shared?.windows.forEach { $0.setEdge("hidden", nil) }
        strips = [:]
        BrowserWindow.editAddress = nil
        Settings.shared.undeclare(owner: id)
        Slots.shared.removeNative("tabstrip", owner: id)
    }

    private func attach(_ w: BrowserWindow) {
        let pos = position
        guard pos != "hidden" else { w.setEdge("hidden", nil); strips[ObjectIdentifier(w)] = nil; return }
        let s = Strip(window: w, vertical: pos == "left" || pos == "right")
        strips[ObjectIdentifier(w)] = s
        w.setEdge(pos, s)
        s.render()
    }

    final class Strip: NSView {
        weak var owner: BrowserWindow?
        let vertical: Bool
        private let stack = NSStackView()
        private let plus = TabButton(plus: true)
        private var pending = false
        private var buttons: [TabButton] = []
        private var editing: TabButton?

        init(window: BrowserWindow, vertical: Bool) {
            self.owner = window
            self.vertical = vertical
            super.init(frame: .zero)
            stack.orientation = vertical ? .vertical : .horizontal
            stack.spacing = 2
            stack.alignment = vertical ? .leading : .centerY
            stack.distribution = .fill
            stack.translatesAutoresizingMaskIntoConstraints = false
            plus.onSelect = { Commands.shared.run("tab.new") }
            if vertical {
                let scroll = NSScrollView()
                scroll.drawsBackground = false
                scroll.hasVerticalScroller = true
                let doc = FlippedView()
                doc.translatesAutoresizingMaskIntoConstraints = false
                doc.addSubview(stack)
                scroll.documentView = doc
                scroll.translatesAutoresizingMaskIntoConstraints = false
                addSubview(scroll)
                NSLayoutConstraint.activate([
                    scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
                    scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                    doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                    stack.topAnchor.constraint(equalTo: doc.topAnchor), stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
                    stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor), stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
                ])
            } else {
                // The + is pinned to the far right; tabs fill the space before it.
                plus.translatesAutoresizingMaskIntoConstraints = false
                addSubview(stack)
                addSubview(plus)
                NSLayoutConstraint.activate([
                    plus.trailingAnchor.constraint(equalTo: trailingAnchor), plus.centerYAnchor.constraint(equalTo: centerYAnchor),
                    stack.leadingAnchor.constraint(equalTo: leadingAnchor),
                    stack.trailingAnchor.constraint(lessThanOrEqualTo: plus.leadingAnchor, constant: -8),
                    stack.centerYAnchor.constraint(equalTo: centerYAnchor),
                ])
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Coalesces bursts of change notifications (loading progress fires many).
        func setNeedsRender() {
            guard !pending, editing == nil else { return }   // typed text must survive progress updates
            pending = true
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.pending = false; self?.render() } }
        }

        /// Turns the focused tab into an address field holding the full URL.
        func edit() -> Bool {
            guard editing == nil, let w = owner, let t = w.tab, buttons.indices.contains(w.activeIndex) else { return false }
            let b = buttons[w.activeIndex]
            editing = b
            b.edit(t.url?.absoluteString ?? "") { [weak self, weak w] end in
                guard let self, let w else { return }
                self.editing = nil
                switch end {
                case .load(let text): w.load(text)
                case .cancel: w.window?.makeFirstResponder(w.tab.flatMap { $0.hasWebView ? $0.webView : nil })
                case .down(let text): BrowserWindow.prompt?(w, text == w.tab?.url?.absoluteString ? "" : text, false)
                case .blur: break
                }
                self.setNeedsRender()
            }
            return true
        }

        func render() {
            guard let w = owner else { return }
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            buttons = []
            var firstPlain: TabButton?
            for (i, t) in w.tabs.enumerated() {
                let focused = i == w.activeIndex
                let b = TabButton(title: focused && !vertical ? (t.url == nil ? "New Tab" : Address.displayHost(t.url)) : t.title,
                                  icon: t.favicon, selected: focused, loading: t.hasWebView && t.webView.isLoading, capsule: focused && !vertical)
                b.onSelect = { [weak w] in w?.select(i) }
                b.onClose = { [weak w] in w?.close(at: i) }
                stack.addArrangedSubview(b)
                buttons.append(b)
                if vertical { b.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; continue }
                // Unfocused tabs share one width (150 ideally) and shrink together; the focused one is wider and shrinks last.
                let ideal = b.widthAnchor.constraint(equalToConstant: focused ? 360 : 150)
                ideal.priority = .init(700)
                ideal.isActive = true
                b.setContentCompressionResistancePriority(.init(focused ? 650 : 600), for: .horizontal)
                if !focused {
                    if let f = firstPlain { b.widthAnchor.constraint(equalTo: f.widthAnchor).isActive = true } else { firstPlain = b }
                }
            }
            if vertical { stack.addArrangedSubview(plus) }
        }
    }

    final class FlippedView: NSView { override var isFlipped: Bool { true } }

    /// One tab (favicon + title), the focused tab's glass capsule (host only), or the + circle.
    final class TabButton: NSView {
        var onSelect: () -> Void = {}
        var onClose: () -> Void = {}
        private let selected: Bool
        private let close = NSButton()
        private var tracking: NSTrackingArea?
        private var row = NSStackView()
        private var host: NSView?
        private var field: NSTextField?
        private var onEnd: ((End) -> Void)?
        enum End { case load(String), cancel, down(String), blur }

        init(title: String = "", icon: NSImage? = nil, selected: Bool = false, loading: Bool = false, capsule: Bool = false, plus: Bool = false) {
            self.selected = selected
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 6
            if selected && !capsule { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor }
            var host: NSView = self
            if capsule || plus {
                let g = Glass.make(cornerRadius: 14)
                g.view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(g.view)
                NSLayoutConstraint.activate([g.view.topAnchor.constraint(equalTo: topAnchor), g.view.bottomAnchor.constraint(equalTo: bottomAnchor),
                                             g.view.leadingAnchor.constraint(equalTo: leadingAnchor), g.view.trailingAnchor.constraint(equalTo: trailingAnchor)])
                host = g.content
            }
            NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 28)])
            if plus {
                let p = NSImageView(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab") ?? NSImage())
                p.symbolConfiguration = .init(pointSize: 12, weight: .medium)
                p.contentTintColor = .labelColor
                p.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(p)
                NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 28), p.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                                             p.centerYAnchor.constraint(equalTo: host.centerYAnchor)])
                return
            }
            let iconView = NSImageView(image: icon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage())
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.contentTintColor = .secondaryLabelColor
            let label = NSTextField(labelWithString: (loading ? "◌ " : "") + title)
            label.font = .systemFont(ofSize: capsule ? 13 : 12)
            label.textColor = selected ? .labelColor : .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
            close.isBordered = false
            close.imageScaling = .scaleProportionallyDown
            close.target = self
            close.action = #selector(closeTapped)
            close.isHidden = true
            self.host = host
            row = NSStackView(views: [iconView, label])
            row.spacing = 6
            for v in [row, close] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(v) }
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 16), iconView.heightAnchor.constraint(equalToConstant: 16),
                row.centerYAnchor.constraint(equalTo: host.centerYAnchor),
                row.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -4),
                close.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
                close.centerYAnchor.constraint(equalTo: host.centerYAnchor),
                close.widthAnchor.constraint(equalToConstant: 14), close.heightAnchor.constraint(equalToConstant: 14),
                capsule ? row.centerXAnchor.constraint(equalTo: host.centerXAnchor) : row.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10),
            ])
            row.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 10).isActive = true
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Replaces the title with a borderless field; `done` runs once when editing ends.
        func edit(_ text: String, done: @escaping (End) -> Void) {
            guard let host, field == nil else { return }
            let f = NSTextField(string: text)
            f.isBordered = false
            f.drawsBackground = false
            f.focusRingType = .none
            f.font = .systemFont(ofSize: selected && host !== self ? 13 : 12)
            f.alignment = host !== self ? .center : .left
            f.cell?.isScrollable = true
            f.cell?.wraps = false
            f.delegate = self
            f.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(f)
            NSLayoutConstraint.activate([f.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10), f.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -4),
                                         f.centerYAnchor.constraint(equalTo: host.centerYAnchor)])
            row.isHidden = true
            field = f
            onEnd = done
            window?.makeFirstResponder(f)
            f.currentEditor()?.selectAll(nil)
        }

        fileprivate func finish(_ end: End) {
            guard let f = field else { return }
            field = nil
            row.isHidden = false
            f.removeFromSuperview()
            let done = onEnd
            onEnd = nil
            done?(end)
        }

        override func updateTrackingAreas() {
            if let t = tracking { removeTrackingArea(t) }
            tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
            addTrackingArea(tracking!)
        }
        override func mouseEntered(with e: NSEvent) {
            close.isHidden = false
            if !selected { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor }
        }
        override func mouseExited(with e: NSEvent) {
            close.isHidden = true
            if !selected { layer?.backgroundColor = nil }
        }
        /// Everything but the × belongs to the tab, so glass and labels never swallow clicks.
        override func hitTest(_ p: NSPoint) -> NSView? {
            let v = super.hitTest(p)
            if field != nil { return v }
            return v is NSButton ? v : v == nil ? nil : self
        }
        override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
        override func mouseDown(with e: NSEvent) { onSelect() }
        override func otherMouseUp(with e: NSEvent) { if e.buttonNumber == 2 { onClose() } }
        @objc private func closeTapped() { onClose() }
    }
}

extension TabStrip.TabButton: NSTextFieldDelegate {
    // ↵ loads, Esc returns to the page, ↓ opens the palette with the typed text; losing focus just ends editing.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): finish(.load(control.stringValue))
        case #selector(NSResponder.cancelOperation(_:)): finish(.cancel)
        case #selector(NSResponder.moveDown(_:)): finish(.down(control.stringValue))
        default: return false
        }
        return true
    }

    func controlTextDidEndEditing(_ n: Notification) { finish(.blur) }
}
