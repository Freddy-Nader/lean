import AppKit
import WebKit

@MainActor
final class BrowserWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    private let address = NSTextField()
    private let content = NSView()
    private(set) var tabs: [Tab] = []
    private(set) var activeIndex = 0
    var tab: Tab { tabs[activeIndex] }
    private(set) lazy var find = FindBar { [unowned self] in self.tab.webView }
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
        add(Tab(), select: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func layout(in root: NSView) {
        address.placeholderString = "Search or enter address"
        address.bezelStyle = .roundedBezel
        address.focusRingType = .none
        address.font = .systemFont(ofSize: 13)
        address.delegate = self
        address.cell?.isScrollable = true
        address.cell?.wraps = false
        find.field.controlSize = .small
        find.onVisibility = { [weak self] shown in self?.findHeight.constant = shown ? 30 : 0 }
        for v in [content, address, find.field] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        findHeight = find.field.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([findHeight,
            address.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            address.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 80),
            address.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            address.heightAnchor.constraint(equalToConstant: 24),
            find.field.topAnchor.constraint(equalTo: address.bottomAnchor, constant: 6),
            find.field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            find.field.widthAnchor.constraint(equalToConstant: 260),
            content.topAnchor.constraint(equalTo: address.bottomAnchor, constant: 6),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    // MARK: tabs

    /// Inserts after the active tab, like Chrome.
    func add(_ t: Tab, select: Bool) {
        t.onChange = { [weak self] t in self?.refresh(t) }
        t.onOpen = { [weak self] url, background in self?.open(url, background: background, opener: t) }
        let i = tabs.isEmpty ? 0 : activeIndex + 1
        tabs.insert(t, at: i)
        if select { self.select(i) } else if i <= activeIndex { activeIndex += 1 }
        AddonHost.shared.emit("tabCreated", AddonHost.describe(t) as! [String: Any])
    }

    @discardableResult
    func open(_ url: URL, background: Bool, opener: Tab? = nil) -> Tab {
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
        address.stringValue = ""
        refresh(t)
        if t.url == nil { focusAddress() } else { window?.makeFirstResponder(v) }
    }

    func close(at i: Int) {
        guard tabs.indices.contains(i) else { return }
        let t = tabs.remove(at: i)
        Tab.closed.append(t.url)
        AddonHost.shared.emit("tabClosed", AddonHost.describe(t) as! [String: Any])
        t.discard()
        if tabs.isEmpty { return close() }
        if i < activeIndex { activeIndex -= 1 } else if i == activeIndex { select(min(i, tabs.count - 1)) }
    }

    func move(by d: Int) {
        let j = activeIndex + d
        guard tabs.indices.contains(j) else { return }
        tabs.swapAt(activeIndex, j)
        activeIndex = j
    }

    func cycle(_ d: Int) { select((activeIndex + d + tabs.count) % tabs.count) }

    func load(_ input: String) {
        guard let url = Address.resolve(input) else { return }
        tab.load(url)
        window?.makeFirstResponder(tab.webView)
    }

    func focusAddress() {
        window?.makeFirstResponder(address)
        address.currentEditor()?.selectAll(nil)
    }

    private func refresh(_ t: Tab) {
        guard t === tab else { return }
        window?.title = t.title
        if address.currentEditor() == nil { address.stringValue = t.url?.absoluteString ?? "" }
    }

    // Enter in the address field loads; Esc restores the current URL and returns to the page.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            load(address.stringValue); return true
        case #selector(NSResponder.cancelOperation(_:)):
            address.stringValue = tab.url?.absoluteString ?? ""
            window?.makeFirstResponder(tab.webView); return true
        default: return false
        }
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
