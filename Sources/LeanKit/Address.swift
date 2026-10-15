import Foundation

/// Turns address-bar input into a URL: a URL as typed, a bare domain, or a web search.
@MainActor
public enum Address {
    static var searchTemplate: String { Settings.shared.string("search.template") }

    public static func resolve(_ raw: String) -> URL? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about", "data", "lean"].contains(scheme) {
            return url
        }
        if looksLikeHost(input), let url = URL(string: (isLocal(input) ? "http://" : "https://") + input) {
            return url
        }
        if let custom = Slots.shared.call("search", "url", [input]) as? String, let u = URL(string: custom) { return u }
        let q = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(["&", "+", "="])) ?? input
        return URL(string: searchTemplate.replacingOccurrences(of: "%s", with: q))
    }

    /// What a tab shows for its URL: the host without `www.`, nothing after the TLD.
    public static func displayHost(_ url: URL?) -> String {
        guard let url else { return "" }
        if url.scheme == "file" { return url.lastPathComponent }
        let host = url.host() ?? ""
        if url.scheme == "lean" { return "lean://" + host }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func looksLikeHost(_ s: String) -> Bool {
        if s.contains(" ") { return false }
        if isLocal(s) { return true }
        let host = s.split(separator: "/", maxSplits: 1).first.map(String.init) ?? s
        let parts = host.split(separator: ":").first?.split(separator: ".") ?? []
        guard parts.count >= 2, let tld = parts.last else { return false }
        return tld.count >= 2 && tld.allSatisfy(\.isLetter)
    }

    private static func isLocal(_ s: String) -> Bool {
        s.hasPrefix("localhost") || s.range(of: #"^\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil
    }
}
