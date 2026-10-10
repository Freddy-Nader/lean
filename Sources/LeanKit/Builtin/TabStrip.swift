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
        set { Settings.shared.set("tabstrip.position", newValue); App.shared?.windows.forEach(attach) }
    }

    func load() throws {
        Slots.shared.provideNative("tabstrip", owner: id)
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: BrowserWindow.opened, object: nil, queue: .main) { n in
                let w = n.object as? BrowserWindow
                MainActor.assumeIsolated { if let w { self.attach(w) } }
            },
            nc.addObserver(forName: BrowserWindow.tabsChanged, object: nil, queue: .main) { n in
                let w = n.object as? BrowserWindow
                MainActor.assumeIsolated { if let w { self.strips[ObjectIdentifier(w)]?.setNeedsRender() } }
            },
        ]
        App.shared?.windows.forEach(attach)
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
        private var pending = false

        init(window: BrowserWindow, vertical: Bool) {
            self.owner = window
            self.vertical = vertical
            super.init(frame: .zero)
            stack.orientation = vertical ? .vertical : .horizontal
            stack.spacing = 2
            stack.alignment = vertical ? .leading : .centerY
            stack.distribution = .fill
            stack.translatesAutoresizingMaskIntoConstraints = false
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
                addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
                    stack.topAnchor.constraint(equalTo: topAnchor, constant: 2), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
                ])
            }
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Coalesces bursts of change notifications (loading progress fires many).
        func setNeedsRender() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.pending = false; self?.render() } }
        }

        func render() {
            guard let w = owner else { return }
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            var first: TabButton?
            for (i, t) in w.tabs.enumerated() {
                let b = TabButton(title: t.title, selected: i == w.activeIndex, loading: t.hasWebView && t.webView.isLoading)
                b.onSelect = { [weak w] in w?.select(i) }
                b.onClose = { [weak w] in w?.close(at: i) }
                stack.addArrangedSubview(b)
                if vertical { b.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
                else {
                    // Equal widths, 200pt ideally, shrinking together when there are many tabs.
                    let ideal = b.widthAnchor.constraint(equalToConstant: 200)
                    ideal.priority = .init(700)
                    ideal.isActive = true
                    b.setContentCompressionResistancePriority(.init(600), for: .horizontal)
                    if let f = first { b.widthAnchor.constraint(equalTo: f.widthAnchor).isActive = true } else { first = b }
                }
            }
            let plus = TabButton(title: "+", selected: false, loading: false, plain: true)
            plus.onSelect = { [weak w] in w?.add(Tab(), select: true) }
            stack.addArrangedSubview(plus)
            if !vertical { plus.widthAnchor.constraint(equalToConstant: 28).isActive = true }
        }
    }

    final class FlippedView: NSView { override var isFlipped: Bool { true } }

    final class TabButton: NSView {
        var onSelect: () -> Void = {}
        var onClose: () -> Void = {}
        private let selected: Bool
        private let close = NSButton()
        private var tracking: NSTrackingArea?

        init(title: String, selected: Bool, loading: Bool, plain: Bool = false) {
            self.selected = selected
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 6
            if selected { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor }
            let label = NSTextField(labelWithString: (loading ? "◌ " : "") + title)
            label.font = .systemFont(ofSize: 12)
            label.textColor = selected || plain ? .labelColor : .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.alignment = plain ? .center : .left
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
            close.isBordered = false
            close.imageScaling = .scaleProportionallyDown
            close.target = self
            close.action = #selector(closeTapped)
            close.isHidden = true
            for v in [label, close] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 26),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: plain ? 0 : 10),
                label.trailingAnchor.constraint(equalTo: plain ? trailingAnchor : close.leadingAnchor, constant: plain ? 0 : -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                close.centerYAnchor.constraint(equalTo: centerYAnchor),
                close.widthAnchor.constraint(equalToConstant: plain ? 0 : 14),
                close.heightAnchor.constraint(equalToConstant: 14),
            ])
            if plain { close.removeFromSuperview() }
        }

        required init?(coder: NSCoder) { fatalError() }

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
        override func mouseDown(with e: NSEvent) { onSelect() }
        override func otherMouseUp(with e: NSEvent) { if e.buttonNumber == 2 { onClose() } }
        @objc private func closeTapped() { onClose() }
    }
}
