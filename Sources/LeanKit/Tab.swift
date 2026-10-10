import AppKit
import WebKit

/// One tab = one WKWebView. The web view is created lazily so restored tabs cost nothing until shown.
@MainActor
final class Tab: NSObject, WKUIDelegate, WKNavigationDelegate {
    /// Shared settings; each tab gets a copy with its own user content controller.
    static let base: WKWebViewConfiguration = {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        c.preferences.isElementFullscreenEnabled = true
        c.mediaTypesRequiringUserActionForPlayback = []
        c.setURLSchemeHandler(AddonsPage.shared, forURLScheme: "lean")
        return c
    }()

    static func makeConfiguration() -> WKWebViewConfiguration {
        let c = base.copy() as! WKWebViewConfiguration
        c.userContentController = WKUserContentController()
        Rules.shared.attach(c.userContentController)
        AddonHost.shared.attach(c.userContentController)
        c.userContentController.add(WeakHandler(AddonsPage.shared), name: "leanAddons")
        return c
    }

    let id = UUID()
    private(set) var pendingURL: URL?
    var onChange: ((Tab) -> Void)?
    /// Asks the window to open a URL in a new tab (target=_blank, ⌘-click, window.open).
    var onOpen: ((URL, _ background: Bool) -> Void)?
    /// Recently closed tab URLs for ⌘⇧T, app-wide.
    static var closed: [URL?] = []
    private var observations: [NSKeyValueObservation] = []

    private(set) lazy var webView: WKWebView = {
        let v = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        v.isInspectable = true
        v.allowsBackForwardNavigationGestures = true
        v.allowsMagnification = true
        v.customUserAgent = Self.userAgent
        v.uiDelegate = self
        v.navigationDelegate = self
        observations = [
            v.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            v.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
            v.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.changed() } },
        ]
        hasWebView = true
        return v
    }()
    private(set) var hasWebView = false

    init(url: URL? = nil) {
        pendingURL = url
        super.init()
    }

    var title: String {
        if hasWebView, let t = webView.title, !t.isEmpty { return t }
        return url?.host() ?? "New Tab"
    }
    var url: URL? { hasWebView ? (webView.url ?? pendingURL) : pendingURL }

    func load(_ url: URL) {
        pendingURL = url
        webView.load(URLRequest(url: url))
    }

    /// Called when the tab becomes visible; loads a deferred URL.
    func materialize() {
        if !hasWebView, let u = pendingURL { load(u) } else { _ = webView }
    }

    /// Starts loading without being shown (background tabs).
    func materializeInBackground() { if !hasWebView, let u = pendingURL { load(u) } }

    func discard() {
        guard hasWebView else { return }
        webView.stopLoading()
        webView.removeFromSuperview()
        observations = []
    }

    private func changed() { onChange?(self) }

    // MARK: new tabs from the page

    func webView(_ v: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = a.request.url { onOpen?(url, a.modifierFlags.contains(.command)) }
        return nil
    }

    func webView(_ v: WKWebView, decidePolicyFor a: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if a.shouldPerformDownload { return decisionHandler(.download) }
        if a.targetFrame?.isMainFrame ?? true, let url = a.request.url {
            Rules.shared.sync(v.configuration.userContentController, topHost: url.host())
            if let r = AddonHost.shared.emit("beforeNavigate", ["url": url.absoluteString, "tab": AddonHost.describe(self)]) {
                if r["cancel"] as? Bool == true { return decisionHandler(.cancel) }
                if let to = r["redirect"] as? String, let u = Address.resolve(to), u != url {
                    decisionHandler(.cancel)
                    return load(u)
                }
            }
        }
        if a.navigationType == .linkActivated, a.modifierFlags.contains(.command), let url = a.request.url {
            onOpen?(url, !a.modifierFlags.contains(.shift))
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
        AddonHost.shared.emit("tabLoaded", ["id": id.uuidString, "url": url?.absoluteString ?? "", "title": title])
    }

    // MARK: downloads

    func webView(_ v: WKWebView, decidePolicyFor r: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let attachment = (r.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment") ?? false
        decisionHandler(r.canShowMIMEType && !attachment ? .allow : .download)
    }

    func webView(_ v: WKWebView, navigationAction a: WKNavigationAction, didBecome d: WKDownload) { Downloads.shared.track(d) }
    func webView(_ v: WKWebView, navigationResponse r: WKNavigationResponse, didBecome d: WKDownload) { Downloads.shared.track(d) }

    // Safari's UA, so sites serve the same pages they serve Safari.
    static let userAgent: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(v.majorVersion).0 Safari/605.1.15"
    }()
}
