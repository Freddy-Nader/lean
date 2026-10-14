import AppKit
import WebKit

@MainActor
final class BrowserWindow: NSWindowController, NSWindowDelegate {
    /// Posted (object: the window) whenever tabs are added, removed, moved, selected or retitled.
    static let tabsChanged = Notification.Name("lean.tabsChanged")
    static let opened = Notification.Name("lean.windowOpened")
    /// Set by the tab strip: turns the focused tab into an address field. Returns false if it can't
    /// (strip hidden, no tab), and the kernel falls back to the palette.
    static var editAddress: ((BrowserWindow) -> Bool)?
    /// Set by the palette add-on: opens it on this window with `text`; `newTab` makes ↵ open a new tab.
    static var prompt: ((BrowserWindow, _ text: String, _ newTab: Bool) -> Void)?

    var onClose: (() -> Void)?
    private var edgeView: NSView?
    private var edge = "hidden"
    private var edgeConstraints: [NSLayoutConstraint] = []
    /// Bottom edge of the top row (nav, tabs, +).
    private let bar = NSLayoutGuide()
    private let nav = Glass.make(cornerRadius: 14)
    private var navButtons: [NSButton] = []
    /// Centre of the traffic lights from the window top: the top row is centred on it.
    private var rowCentre: CGFloat = 16
    private let content = NSView()
    private(set) var tabs: [Tab] = []
    private(set) var activeIndex = 0
    var tab: Tab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }
    private(set) lazy var find = FindBar { [unowned self] in self.tab?.webView }
    private var findHeight: NSLayoutConstraint!

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("lean.main")
        if w.frame.origin == .zero { w.center() }
        super.init(window: w)
        w.delegate = self
        layout(in: w.contentView!)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layout(in root: NSView) {
        let close = window?.standardWindowButton(.closeButton), zoom = window?.standardWindowButton(.zoomButton)
        if let close, let p = close.superview {
            let c = root.bounds.height - root.convert(close.frame, from: p).midY
            if (8...30).contains(c) { rowCentre = c }
        }
        var zoomRight: CGFloat = 69
        if let zoom, let p = zoom.superview, root.convert(zoom.frame, from: p).maxX > 40 { zoomRight = root.convert(zoom.frame, from: p).maxX }
        navButtons = [("chevron.left", "page.back"), ("chevron.right", "page.forward"), ("arrow.clockwise", "page.reload")].map { icon, cmd in
            let b = NSButton(image: NSImage(systemSymbolName: icon, accessibilityDescription: cmd) ?? NSImage(), target: self, action: #selector(navTapped(_:)))
            b.isBordered = false
            b.identifier = .init(cmd)
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true
            return b
        }
        let navStack = NSStackView(views: navButtons)
        navStack.spacing = 0
        navStack.translatesAutoresizingMaskIntoConstraints = false
        nav.content.addSubview(navStack)
        nav.view.isHidden = true
        nav.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(nav.view)
        NSLayoutConstraint.activate([
            nav.view.topAnchor.constraint(equalTo: root.topAnchor, constant: rowCentre - 14), nav.view.heightAnchor.constraint(equalToConstant: 28),
            nav.view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: zoomRight + 12),
            navStack.leadingAnchor.constraint(equalTo: nav.content.leadingAnchor, constant: 6), navStack.trailingAnchor.constraint(equalTo: nav.content.trailingAnchor, constant: -6),
            navStack.centerYAnchor.constraint(equalTo: nav.content.centerYAnchor),
        ])
        find.field.controlSize = .small
        find.onVisibility = { [weak self] shown in self?.findHeight.constant = shown ? 30 : 0 }
        root.addLayoutGuide(bar)
        for v in [content, find.field] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        findHeight = find.field.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([findHeight,
            bar.topAnchor.constraint(equalTo: root.topAnchor), bar.heightAnchor.constraint(equalToConstant: rowCentre * 2 - 2),
            find.field.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            find.field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            find.field.widthAnchor.constraint(equalToConstant: 260),
        ])
        layoutEdge()
    }

    // MARK: edge (tab strip) layout

    /// Places an add-on view along one edge: "top", "bottom", "left", "right"; "hidden" or nil removes it.
    func setEdge(_ edge: String, _ view: NSView?) {
        edgeView?.removeFromSuperview()
        self.edge = view == nil ? "hidden" : edge
        edgeView = view
        layoutEdge()
    }

    private func layoutEdge() {
        guard let root = window?.contentView else { return }
        NSLayoutConstraint.deactivate(edgeConstraints)
        let top = bar.bottomAnchor
        var c: [NSLayoutConstraint] = []
        if let v = edgeView, edge != "hidden" {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v, positioned: .above, relativeTo: content)
            switch edge {
            case "top":
                c += [v.centerYAnchor.constraint(equalTo: root.topAnchor, constant: rowCentre), v.heightAnchor.constraint(equalToConstant: 28),
                      v.leadingAnchor.constraint(equalTo: nav.view.trailingAnchor, constant: 8), v.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
                      content.topAnchor.constraint(equalTo: top, constant: 6), content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                      content.leadingAnchor.constraint(equalTo: root.leadingAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor)]
            case "bottom":
                c += [v.bottomAnchor.constraint(equalTo: root.bottomAnchor), v.heightAnchor.constraint(equalToConstant: 30),
                      v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                      content.topAnchor.constraint(equalTo: top, constant: 6), content.bottomAnchor.constraint(equalTo: v.topAnchor),
                      content.leadingAnchor.constraint(equalTo: root.leadingAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor)]
            default: // left / right sidebar
                let left = edge == "left"
                c += [v.topAnchor.constraint(equalTo: top, constant: 6), v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                      v.widthAnchor.constraint(equalToConstant: 220),
                      left ? v.leadingAnchor.constraint(equalTo: root.leadingAnchor) : v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                      content.topAnchor.constraint(equalTo: top, constant: 6), content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                      left ? content.leadingAnchor.constraint(equalTo: v.trailingAnchor) : content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                      left ? content.trailingAnchor.constraint(equalTo: root.trailingAnchor) : content.trailingAnchor.constraint(equalTo: v.leadingAnchor)]
            }
        } else {
            c += [content.topAnchor.constraint(equalTo: top, constant: 6), content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                  content.leadingAnchor.constraint(equalTo: root.leadingAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor)]
        }
        edgeConstraints = c
        NSLayoutConstraint.activate(c)
    }

    private func changed() {
        nav.view.isHidden = tabs.isEmpty
        let v = tab.flatMap { $0.hasWebView ? $0.webView : nil }
        navButtons[0].isEnabled = v?.canGoBack ?? false
        navButtons[1].isEnabled = v?.canGoForward ?? false
        NotificationCenter.default.post(name: Self.tabsChanged, object: self)
    }

    @objc private func navTapped(_ b: NSButton) { if let id = b.identifier?.rawValue { Commands.shared.run(id) } }

    // MARK: tabs

    /// Inserts after the active tab, like Chrome.
    func add(_ t: Tab, select: Bool) {
        t.onChange = { [weak self] t in self?.refresh(t) }
        t.onOpen = { [weak self] url, background in
            // Pages may not open file: or data: URLs; loading them natively would skip WebKit's block.
            guard ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") else { return }
            self?.open(url, background: background)
        }
        let i = tabs.isEmpty ? 0 : activeIndex + 1
        let select = select || tabs.isEmpty
        tabs.insert(t, at: i)
        if select { self.select(i) } else if i <= activeIndex { activeIndex += 1 }
        changed()
        AddonHost.shared.emit("tabCreated", AddonHost.describe(t) as! [String: Any])
    }

    @discardableResult
    func open(_ url: URL, background: Bool) -> Tab {
        let t = Tab(url: url)
        add(t, select: !background)
        if background { t.materializeInBackground() }
        return t
    }

    func select(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        activeIndex = i
        let t = tabs[i]
        t.materialize()
        content.subviews.forEach { $0.removeFromSuperview() }
        let v = t.webView
        v.frame = content.bounds
        v.autoresizingMask = [.width, .height]
        content.addSubview(v)
        refresh(t)
        if t.url == nil { focusAddress() } else { window?.makeFirstResponder(v) }
        changed()
    }

    func close(at i: Int) {
        guard tabs.indices.contains(i) else { return }
        let t = tabs.remove(at: i)
        Tab.closed.append(t.url)
        AddonHost.shared.emit("tabClosed", AddonHost.describe(t) as! [String: Any])
        t.discard()
        if tabs.isEmpty {
            content.subviews.forEach { $0.removeFromSuperview() }
            activeIndex = 0
            window?.title = "lean"
            return changed()
        }
        if i < activeIndex { activeIndex -= 1 } else if i == activeIndex { select(min(i, tabs.count - 1)) }
        changed()
    }

    func move(by d: Int) {
        let j = activeIndex + d
        guard tabs.indices.contains(j) else { return }
        tabs.swapAt(activeIndex, j)
        activeIndex = j
        changed()
    }

    func cycle(_ d: Int) { select((activeIndex + d + tabs.count) % tabs.count) }

    func load(_ input: String) {
        guard let url = Address.resolve(input) else { return }
        guard let tab else { open(url, background: false); return }
        tab.load(url)
        window?.makeFirstResponder(tab.webView)
    }

    /// ⌘L: edit the focused tab in place; without a strip, ask the palette.
    func focusAddress() {
        if Self.editAddress?(self) == true { return }
        Self.prompt?(self, tab?.url?.absoluteString ?? "", false)
    }

    private func refresh(_ t: Tab) {
        changed()
        guard let tab, t === tab else { return }
        window?.title = t.title
    }

    // MARK: toast

    private var toastLabel: NSTextField?

    func toast(_ text: String) {
        guard let root = window?.contentView else { return }
        toastLabel?.removeFromSuperview()
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.textColor = .white
        l.wantsLayer = true
        l.drawsBackground = true
        l.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        l.layer?.cornerRadius = 6
        l.alignment = .center
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            l.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            l.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -48),
            l.heightAnchor.constraint(equalToConstant: 26),
        ])
        toastLabel = l
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak l] in
            MainActor.assumeIsolated { if self?.toastLabel === l { l?.removeFromSuperview() } }
        }
    }

    func windowWillClose(_ n: Notification) {
        tabs.forEach { $0.discard() }
        onClose?()
    }
}
