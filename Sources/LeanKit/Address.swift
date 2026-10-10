import Foundation

/// Turns address-bar input into a URL: a URL as typed, a bare domain, or a web search.
@MainActor
public enum Address {
    static var searchTemplate = "https://www.google.com/search?q=%s"

    public static func resolve(_ raw: String) -> URL? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about", "data"].contains(scheme) {
            return url
        }
        if looksLikeHost(input), let url = URL(string: (isLocal(input) ? "http://" : "https://") + input) {
            return url
        }
        let q = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(["&", "+", "="])) ?? input
        return URL(string: searchTemplate.replacingOccurrences(of: "%s", with: q))
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
        s.hasPrefix("localhost") || s.hasPrefix("127.0.0.1") || s.range(of: #"^\d+\.\d+\.\d+\.\d+"#, options: .regularExpression) != nil
    }
}
