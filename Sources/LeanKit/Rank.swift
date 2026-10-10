import Foundation

/// Kernel ranking service shared by every list the user picks from (palette, suggestions).
/// Score = how well the text matches × how often and how recently it was picked (frecency).
/// Picks are logged locally in ~/.config/lean/rank.json so the weights can be tuned with evidence.
@MainActor
public final class Rank {
    public static let shared = Rank()

    /// Half-life of a pick's weight, in days.
    var halfLife: Double = 30
    private var picks: [String: [Double]] = [:]   // key → pick timestamps
    private var dirty = false
    static var file: URL { Commands.configDir.appending(path: "rank.json") }

    init() {
        if let d = try? Data(contentsOf: Self.file), let p = try? JSONDecoder().decode([String: [Double]].self, from: d) {
            picks = p
        }
    }

    /// Record that the user chose `key` (e.g. "tab:https://…", "cmd:tab.new").
    public func pick(_ key: String, now: Date = Date()) {
        picks[key, default: []].append(now.timeIntervalSince1970)
        if picks[key]!.count > 30 { picks[key]!.removeFirst() }
        save()
    }

    public func forget(_ key: String) {
        picks[key] = nil
        save()
    }

    /// Sum of decayed weights of past picks; 0 when never picked.
    public func frecency(_ key: String, now: Date = Date()) -> Double {
        let t = now.timeIntervalSince1970
        return (picks[key] ?? []).reduce(0) { $0 + pow(0.5, (t - $1) / 86_400 / halfLife) }
    }

    /// Final score: match quality first, frecency breaks ties and lifts habits.
    public func score(query: String, text: String, key: String) -> Double? {
        guard let m = Self.match(query, text) else { return nil }
        return m * (1 + log1p(frecency(key)))
    }

    /// Fuzzy subsequence match in [0, 1]. Prefix > word start > contiguous > scattered.
    /// nil when not every query character appears in order.
    nonisolated public static func match(_ query: String, _ text: String) -> Double? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        if q.isEmpty { return 0.5 }
        let t = Array(text.lowercased())
        if text.lowercased().hasPrefix(query.lowercased()) { return 1 }
        var qi = 0, score = 0.0, last = -2
        for (i, ch) in t.enumerated() where qi < q.count && ch == q[qi] {
            let wordStart = i == 0 || !t[i - 1].isLetter && !t[i - 1].isNumber
            score += wordStart ? 3 : (i == last + 1 ? 2 : 1)
            last = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        let m = score / Double(q.count * 3)
        // Letters scattered across unrelated words ("tab" in "github · change") are noise.
        return q.count >= 3 && m < 0.4 ? nil : min(0.95, m)
    }

    private func save() {
        guard !dirty else { return }
        dirty = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.dirty = false
                if let d = try? JSONEncoder().encode(self.picks) { try? d.write(to: Self.file) }
            }
        }
    }
}
