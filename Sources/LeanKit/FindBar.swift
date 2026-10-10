import AppKit
import WebKit

/// ⌘F bar. Uses WKWebView's public find API; WebKit highlights and scrolls to the match.
@MainActor
final class FindBar: NSObject, NSSearchFieldDelegate {
    let field = NSSearchField()
    var webView: () -> WKWebView?
    var onVisibility: (Bool) -> Void = { _ in }

    init(webView: @escaping () -> WKWebView?) {
        self.webView = webView
        super.init()
        field.placeholderString = "Find in page"
        field.delegate = self
        field.isHidden = true
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(changed)
    }

    func open() {
        field.isHidden = false
        onVisibility(true)
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func close() {
        field.isHidden = true
        onVisibility(false)
        field.window?.makeFirstResponder(webView())
    }

    func next(backwards: Bool) {
        guard !field.stringValue.isEmpty else { return open() }
        let c = WKFindConfiguration()
        c.backwards = backwards
        c.wraps = true
        webView()?.find(field.stringValue, configuration: c) { _ in }
    }

    @objc private func changed() { next(backwards: false) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            next(backwards: NSEvent.modifierFlags.contains(.shift)); return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(); return true
        default: return false
        }
    }
}
