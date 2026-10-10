import AppKit

/// Liquid Glass on macOS 26, the older blur before. Add subviews to `content`, not `view`.
@MainActor
enum Glass {
    static func make(cornerRadius: CGFloat) -> (view: NSView, content: NSView) {
        let content = NSView()
        if #available(macOS 26, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = cornerRadius
            g.contentView = content
            return (g, content)
        }
        let v = NSVisualEffectView()
        v.material = .popover
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(content)
        NSLayoutConstraint.activate([content.topAnchor.constraint(equalTo: v.topAnchor), content.bottomAnchor.constraint(equalTo: v.bottomAnchor),
                                     content.leadingAnchor.constraint(equalTo: v.leadingAnchor), content.trailingAnchor.constraint(equalTo: v.trailingAnchor)])
        return (v, content)
    }
}
