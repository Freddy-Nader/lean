import AppKit
import WebKit

@MainActor
final class BrowserWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    private let address = NSTextField()
    private let content = NSView()
    private(set) var tab = Tab()
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
        show(tab)
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

    func show(_ t: Tab) {
        tab = t
        t.onChange = { [weak self] t in self?.refresh(t) }
        t.materialize()
        content.subviews.forEach { $0.removeFromSuperview() }
        let v = t.webView
        v.frame = content.bounds
        v.autoresizingMask = [.width, .height]
        content.addSubview(v)
        refresh(t)
    }

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

    func windowWillClose(_ n: Notification) { onClose?() }
}
