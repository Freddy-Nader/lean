import AppKit
import WebKit

/// One tab = one WKWebView. The web view is created lazily so restored tabs cost nothing until shown.
@MainActor
final class Tab: NSObject {
    static let configuration: WKWebViewConfiguration = {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        c.preferences.isElementFullscreenEnabled = true
        c.mediaTypesRequiringUserActionForPlayback = []
        return c
    }()

    let id = UUID()
    private(set) var pendingURL: URL?
    var onChange: ((Tab) -> Void)?
    private var observations: [NSKeyValueObservation] = []

    private(set) lazy var webView: WKWebView = {
        let v = WKWebView(frame: .zero, configuration: Self.configuration)
        v.isInspectable = true
        v.allowsBackForwardNavigationGestures = true
        v.allowsMagnification = true
        v.customUserAgent = Self.userAgent
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

    private func changed() { onChange?(self) }

    // Safari's UA, so sites serve the same pages they serve Safari.
    static let userAgent: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(v.majorVersion).0 Safari/605.1.15"
    }()
}
