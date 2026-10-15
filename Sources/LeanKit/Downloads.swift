import AppKit
import WebKit

/// Saves downloads to the `downloads.folder` setting (default ~/Downloads). The panel that lists
/// them is an add-on; the kernel only saves files and reports progress.
@MainActor
public final class Downloads: NSObject, WKDownloadDelegate {
    public static let shared = Downloads()

    public struct Item {
        public let source: URL?
        public var file: URL?
        public var done = false
        public var failed = false
    }

    public private(set) var items: [Item] = []
    private var byDownload: [ObjectIdentifier: Int] = [:]
    public var onChange: (() -> Void)?

    func track(_ d: WKDownload) {
        d.delegate = self
        byDownload[ObjectIdentifier(d)] = items.count
        items.append(Item(source: d.originalRequest?.url))
        onChange?()
    }

    public func download(_ d: WKDownload, decideDestinationUsing r: URLResponse, suggestedFilename name: String,
                         completionHandler: @escaping @MainActor (URL?) -> Void) {
        let info: [String: Any] = ["url": d.originalRequest?.url?.absoluteString ?? "", "filename": name]
        let hook = AddonHost.shared.emit("beforeDownload", info)
        if hook?["cancel"] as? Bool == true {
            if let i = byDownload[ObjectIdentifier(d)] { items[i].failed = true }
            return completionHandler(nil)
        }
        let custom = (hook?["path"] as? String)
            ?? (Slots.shared.call("downloads", "destination", [info]) as? String)
        let dest = custom.map { Self.unique(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }
            ?? Self.unique(Settings.shared.path("downloads.folder").appending(path: name))
        if let i = byDownload[ObjectIdentifier(d)] { items[i].file = dest }
        onChange?()
        completionHandler(dest)
    }

    public func downloadDidFinish(_ d: WKDownload) {
        guard let i = byDownload.removeValue(forKey: ObjectIdentifier(d)) else { return }
        items[i].done = true
        if let f = items[i].file {
            // Bounces the Dock's Downloads stack, like Safari.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: f.path)
        }
        onChange?()
    }

    public func download(_ d: WKDownload, didFailWithError e: Error, resumeData: Data?) {
        guard let i = byDownload.removeValue(forKey: ObjectIdentifier(d)) else { return }
        items[i].failed = true
        onChange?()
    }

    /// Saves bytes the page already has (the PDF viewer's download button) to the downloads folder.
    @discardableResult
    func save(_ data: Data, suggestedName: String, source: URL?) -> URL? {
        let name = (suggestedName as NSString).lastPathComponent   // the page picks the name
        let dest = Self.unique(Settings.shared.path("downloads.folder")
            .appending(path: name.isEmpty || name.hasPrefix(".") ? "download.pdf" : name))
        guard (try? data.write(to: dest, options: .withoutOverwriting)) != nil else { return nil }
        items.append(Item(source: source, file: dest, done: true))
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: dest.path)
        onChange?()
        return dest
    }

    /// "file.pdf" → "file 2.pdf" when taken.
    static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        for n in 2... {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = url.deletingLastPathComponent().appending(path: name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}
