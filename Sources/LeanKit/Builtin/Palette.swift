import AppKit

/// ⌘K palette (default add-on, provides the `palette` slot).
/// Notion's grouped results + Raycast's interaction: right-side accessory, action bar,
/// ⌘K action panel on the selected row, push navigation with Esc to go back.
@MainActor
final class Palette: NSObject, SwiftAddon, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let shared = Palette()
    let id = "palette", name = "Palette", kind = JSAddon.Kind.default
    let summary = "⌘K: tabs, commands, settings and add-on groups in one searchable list."

    struct Item {
        var icon: String
        var title: String
        var subtitle = ""
        var accessory = ""
        var key: String
        var primary = "Open"
        var run: () -> Void = {}
        var alt: (() -> Void)? = nil          // ⌘↵
        var actions: [Item] = []
        var push: (() -> Level)? = nil
    }

    struct Level {
        var placeholder: String
        var groups: (String) -> [(String, [Item])]
        var query = ""
    }

    private enum Row { case header(String), item(Item) }

    private var rows: [Row] = []
    private var stack: [Level] = []
    private weak var host: BrowserWindow?
    private let backdrop = Backdrop()
    private let box = NSVisualEffectView()
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let hintLeft = NSTextField(labelWithString: "")
    private let hintRight = NSTextField(labelWithString: "Actions ⌘K")
    private var tableHeight: NSLayoutConstraint!
    private var topNormal: NSLayoutConstraint!
    private var topCentered: NSLayoutConstraint!
    private var newTab = false
    /// A window with no tabs shows the palette centred and it cannot be dismissed.
    private var centered = false

    var isOpen: Bool { backdrop.superview != nil }

    // MARK: SwiftAddon

    func load() throws {
        Commands.shared.register("palette.open", "Open Palette", keys: ["cmd+k"], owner: id) { [weak self] in
            guard let self else { return }
            if self.isOpen { self.showActions() } else { self.open() }
        }
        Slots.shared.provideNative("palette", owner: id)
        BrowserWindow.prompt = { [weak self] w, text, newTab in self?.open(in: w, query: text, newTab: newTab) }
        // shortcut: one shared palette view; with two empty windows it moves to whichever changed last.
        for n in [BrowserWindow.opened, BrowserWindow.tabsChanged] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: n, object: nil)
        }
        build()
    }

    func unload() {
        close()
        Commands.shared.unregister("palette.open")
        Slots.shared.removeNative("palette", owner: id)
        BrowserWindow.prompt = nil
        NotificationCenter.default.removeObserver(self)
    }

    /// Empty window → palette (launch, last tab closed); palette centred on a window that now has tabs → gone.
    @objc private func windowChanged(_ n: Notification) {
        guard let w = n.object as? BrowserWindow else { return }
        if w.tabs.isEmpty {
            if !(isOpen && host === w) { open(in: w) }
        } else if isOpen, centered, host === w { close() }
    }

    // MARK: open / close

    func open(in w: BrowserWindow? = App.shared?.current, query: String = "", newTab: Bool = false) {
        guard let w, let root = w.window?.contentView else { return }
        host = w
        self.newTab = newTab
        centered = w.tabs.isEmpty
        topNormal.isActive = !centered
        topCentered.isActive = centered
        stack = [rootLevel()]
        backdrop.frame = root.bounds
        backdrop.autoresizingMask = [.width, .height]
        root.addSubview(backdrop)
        field.stringValue = query
        stack[0].query = query
        reload()
        w.window?.makeFirstResponder(field)
        field.currentEditor()?.moveToEndOfDocument(nil)
    }

    func close() {
        guard isOpen else { return }
        backdrop.removeFromSuperview()
        if let h = host { h.window?.makeFirstResponder(h.tab.flatMap { $0.hasWebView ? $0.webView : nil }) }
    }

    private func push(_ level: Level) {
        stack[stack.count - 1].query = field.stringValue
        stack.append(level)
        field.stringValue = ""
        reload()
    }

    private func pop() {
        guard stack.count > 1 else {
            if centered { field.stringValue = ""; reload(); return }
            return close()
        }
        stack.removeLast()
        field.stringValue = stack.last!.query
        reload()
    }

    private func showActions() {
        guard let item = selected, !item.actions.isEmpty else { return }
        push(Level(placeholder: "Actions for \(item.title)") { q in
            [("Actions", item.actions.filter { Rank.match(q, $0.title) != nil })]
        })
    }

    // MARK: data

    private func rootLevel() -> Level {
        Level(placeholder: "Search tabs, commands, settings…") { [weak self] q in self?.rootGroups(q) ?? [] }
    }

    private func rootGroups(_ q: String) -> [(String, [Item])] {
        var out: [(String, [Item])] = []
        func ranked(_ items: [Item], limit: Int) -> [Item] {
            items.compactMap { i in Rank.shared.score(query: q, text: i.title + " " + i.subtitle, key: i.key).map { (i, $0) } }
                .sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
        }
        out.append(("Tabs", ranked(tabItems(), limit: q.isEmpty ? 12 : 6)))
        let cmds = ranked(commandItems(), limit: q.isEmpty ? 0 : 6)
        out.append(("Commands", q.isEmpty ? frequentCommands() : cmds))
        out.append(("Settings", q.isEmpty ? [] : ranked(settingItems(), limit: 4)))
        if !q.isEmpty { out.append(("Add-ons", ranked(addonItems(), limit: 4))) }
        for g in PaletteGroups.shared.query(q) {
            out.append((g.group, g.rows.prefix(6).map { r in
                Item(icon: "clock", title: r.title, subtitle: r.subtitle, key: "row:\(r.subtitle)", run: r.run)
            }))
        }
        if !q.trimmingCharacters(in: .whitespaces).isEmpty { out.append(("Web", [webItem(q)])) }
        return out.filter { !$0.1.isEmpty }
    }

    private func tabItems() -> [Item] {
        guard let app = App.shared else { return [] }
        return app.windows.flatMap { w in w.tabs.enumerated().map { (i, t) in
            let url = t.url?.absoluteString ?? ""
            let focus = { w.select(i); w.window?.makeKeyAndOrderFront(nil) }
            return Item(icon: t === w.tab ? "circle.fill" : "globe", title: t.title,
                        subtitle: t.url.map { ($0.host() ?? "") + $0.path } ?? "", accessory: "Tab",
                        key: "tab:\(url)", primary: "Switch to Tab", run: focus, actions: [
                            Item(icon: "doc.on.doc", title: "Copy Link", key: "act:copy", primary: "Copy") {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string)
                            },
                            Item(icon: "arrow.clockwise", title: "Reload", key: "act:reload", primary: "Reload") { t.webView.reload() },
                            Item(icon: "xmark", title: "Close Tab", key: "act:close", primary: "Close") {
                                if let j = w.tabs.firstIndex(where: { $0 === t }) { w.close(at: j) }
                            },
                        ])
        } }
    }

    private func commandItems() -> [Item] {
        Commands.shared.all.values.filter { $0.id != "palette.open" && !$0.id.hasPrefix("tab.select") }.map { c in
            Item(icon: "command", title: c.title, subtitle: c.id, accessory: Commands.shared.key(for: c.id) ?? "Command",
                 key: "cmd:\(c.id)", primary: "Run Command", run: { Commands.shared.run(c.id) })
        }
    }

    private func frequentCommands() -> [Item] {
        commandItems().map { ($0, Rank.shared.frecency($0.key)) }.filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }.prefix(4).map(\.0)
    }

    /// One row per declared setting: choices push a list (✓ on the current value), folders open a panel.
    private func settingItems() -> [Item] {
        let s = Settings.shared
        return s.declared.map { d in
            let cur = s.string(d.key).isEmpty ? (d.options.first?.value ?? "") : s.string(d.key)
            if d.options.isEmpty {
                return Item(icon: d.icon, title: d.title, subtitle: s.string(d.key), accessory: "Setting", key: "set:\(d.key)",
                            primary: "Choose…") { s.chooseFolder(d.key) }
            }
            return Item(icon: d.icon, title: d.title, subtitle: d.options.first { $0.value == cur }?.label ?? cur, accessory: "Setting",
                        key: "set:\(d.key)", primary: "Change", push: {
                Level(placeholder: d.title) { q in
                    [(d.title, d.options.filter { Rank.match(q, $0.label) != nil }.map { o in
                        Item(icon: d.icon, title: o.label, accessory: o.value == cur ? "✓" : "", key: "opt:\(d.key):\(o.value)", primary: "Use") { s.set(d.key, o.value) }
                    })]
                }
            })
        }
    }

    /// Add-ons that are switched off, so they can be found and turned on from the palette.
    private func addonItems() -> [Item] {
        let host = AddonHost.shared
        let all: [(id: String, name: String, summary: String, kind: JSAddon.Kind)] =
            host.addons.values.map { ($0.id, $0.name.isEmpty ? $0.id : $0.name, $0.summary, $0.kind) }
            + SwiftAddons.all.map { ($0.id, $0.name, $0.summary, $0.kind) }
        return all.filter { !host.isEnabled($0.id, $0.kind) }.map { a in
            Item(icon: "puzzlepiece.extension", title: "Turn On \(a.name)", subtitle: a.summary, accessory: "Add-on", key: "addon:\(a.id)",
                 primary: "Turn On") { host.setEnabled(a.id, true); App.shared?.current?.toast("\(a.name) turned on") }
        }
    }

    private func webItem(_ q: String) -> Item {
        let url = Address.resolve(q)
        let isSearch = url == nil || (!Address.looksLikeHost(q) && !q.contains("://"))
        let w = host
        let fresh = newTab || w?.tab == nil
        let inTab = { if let u = url { if let t = w?.tab { t.load(u) } else { w?.open(u, background: false) } } }
        let inNew = { if let u = url { w?.open(u, background: false) } }
        return Item(icon: isSearch ? "magnifyingglass" : "arrow.up.right", title: isSearch ? "Search the web for “\(q)”" : "Open \(q)",
                    subtitle: url?.host() ?? "", accessory: w?.tab == nil ? "" : fresh ? "⌘↵ this tab" : "⌘↵ new tab", key: "web", primary: isSearch ? "Search" : "Open",
                    run: fresh ? inNew : inTab, alt: w?.tab == nil ? nil : fresh ? inTab : inNew)
    }

    // MARK: table

    private var selected: Item? {
        guard table.selectedRow >= 0, case .item(let i) = rows[table.selectedRow] else { return nil }
        return i
    }

    private func reload() {
        let level = stack.last!
        field.placeholderString = level.placeholder
        rows = level.groups(field.stringValue).flatMap { g in [Row.header(g.0)] + g.1.map(Row.item) }
        table.reloadData()
        let h = rows.reduce(0.0) { $0 + (isHeader($1) ? 26 : 36) }
        tableHeight.constant = min(h, 380)
        select(firstItem(from: 0, step: 1))
    }

    private func isHeader(_ r: Row) -> Bool { if case .header = r { true } else { false } }

    private func firstItem(from i: Int, step: Int) -> Int? {
        var j = i
        while rows.indices.contains(j) { if !isHeader(rows[j]) { return j }; j += step }
        return nil
    }

    private func select(_ i: Int?) {
        guard let i else { table.deselectAll(nil); hintLeft.stringValue = ""; return }
        table.selectRowIndexes([i], byExtendingSelection: false)
        table.scrollRowToVisible(i)
        if case .item(let it) = rows[i] {
            hintLeft.stringValue = "↵ \(it.primary)"
            hintRight.stringValue = it.actions.isEmpty ? "" : "Actions ⌘K"
        }
    }

    private func move(_ d: Int) {
        let start = table.selectedRow < 0 ? (d > 0 ? 0 : rows.count - 1) : table.selectedRow + d
        if let j = firstItem(from: start, step: d) { select(j) }
    }

    private func nextGroup() {
        var j = max(table.selectedRow, 0) + 1
        while rows.indices.contains(j), !isHeader(rows[j]) { j += 1 }
        select(firstItem(from: j, step: 1) ?? firstItem(from: 0, step: 1))
    }

    private func activate(alt: Bool = false) {
        guard let item = selected else { return }
        Rank.shared.pick(item.key)
        if let p = item.push { return push(p()) }
        close()
        if alt, let a = item.alt { a() } else { item.run() }
        // A command that opened no tab must not leave an empty window with nothing in it.
        if let h = host, h.tabs.isEmpty, !isOpen { open(in: h) }
    }

    func numberOfRows(in t: NSTableView) -> Int { rows.count }
    func tableView(_ t: NSTableView, isGroupRow row: Int) -> Bool { isHeader(rows[row]) }
    func tableView(_ t: NSTableView, shouldSelectRow row: Int) -> Bool { !isHeader(rows[row]) }
    func tableView(_ t: NSTableView, heightOfRow row: Int) -> CGFloat { isHeader(rows[row]) ? 26 : 36 }
    func tableView(_ t: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RowView() }

    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            let v = NSView()
            l.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(l)
            NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
                                         l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4)])
            return v
        case .item(let i):
            return Cell(i)
        }
    }

    @objc private func clicked() {
        guard table.clickedRow >= 0, !isHeader(rows[table.clickedRow]) else { return }
        select(table.clickedRow)
        activate()
    }

    // MARK: keys in the field

    func controlTextDidChange(_ n: Notification) { reload() }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let mods = NSApp.currentEvent?.modifierFlags ?? []
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.insertTab(_:)): nextGroup()
        case #selector(NSResponder.insertNewline(_:)): activate(alt: mods.contains(.command))
        case #selector(NSResponder.cancelOperation(_:)): pop()
        case #selector(NSResponder.deleteBackward(_:)) where mods.contains(.shift):
            if let i = selected { Rank.shared.forget(i.key); reload() }   // ⇧⌫ forgets
        case #selector(NSResponder.deleteBackward(_:)) where field.stringValue.isEmpty && stack.count > 1: pop()
        default: return false
        }
        return true
    }

    // MARK: views

    private func build() {
        box.material = .popover
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.masksToBounds = true
        box.translatesAutoresizingMaskIntoConstraints = false
        backdrop.onClick = { [weak self] in if self?.centered == false { self?.close() } }
        backdrop.addSubview(box)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.delegate = self

        let col = NSTableColumn(identifier: .init("c"))
        table.addTableColumn(col)
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.refusesFirstResponder = true
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false

        let sep1 = NSBox(), sep2 = NSBox()
        sep1.boxType = .separator; sep2.boxType = .separator
        for l in [hintLeft, hintRight] { l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor }

        for v in [field, sep1, scroll, sep2, hintLeft, hintRight] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(v)
        }
        tableHeight = scroll.heightAnchor.constraint(equalToConstant: 200)
        topNormal = box.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 72)
        topCentered = box.topAnchor.constraint(equalTo: backdrop.centerYAnchor, constant: -60)
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            box.widthAnchor.constraint(equalToConstant: 640),
            box.widthAnchor.constraint(lessThanOrEqualTo: backdrop.widthAnchor, constant: -32),
            field.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            sep1.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            sep1.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            sep1.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
            tableHeight,
            sep2.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            sep2.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            sep2.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            hintLeft.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 7),
            hintLeft.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            hintRight.centerYAnchor.constraint(equalTo: hintLeft.centerYAnchor),
            hintRight.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            box.bottomAnchor.constraint(equalTo: hintLeft.bottomAnchor, constant: 8),
        ])
    }

    private final class Backdrop: NSView {
        var onClick: () -> Void = {}
        override func mouseDown(with e: NSEvent) {
            if hitTest(convert(e.locationInWindow, from: nil)) === self { onClick() }
        }
    }

    private final class RowView: NSTableRowView {
        override func drawSelection(in r: NSRect) {
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        override var isEmphasized: Bool { get { false } set {} }
    }

    private final class Cell: NSView {
        init(_ i: Item) {
            super.init(frame: .zero)
            let icon = NSImageView(image: NSImage(systemSymbolName: i.icon, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            let title = NSTextField(labelWithString: i.title)
            title.font = .systemFont(ofSize: 13)
            title.lineBreakMode = .byTruncatingTail
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let sub = NSTextField(labelWithString: i.subtitle)
            sub.font = .systemFont(ofSize: 12)
            sub.textColor = .tertiaryLabelColor
            sub.lineBreakMode = .byTruncatingMiddle
            sub.setContentCompressionResistancePriority(.init(100), for: .horizontal)
            let acc = NSTextField(labelWithString: i.accessory)
            acc.font = .systemFont(ofSize: 11)
            acc.textColor = .secondaryLabelColor
            acc.setContentCompressionResistancePriority(.required, for: .horizontal)
            for v in [icon, title, sub, acc] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                title.centerYAnchor.constraint(equalTo: centerYAnchor),
                title.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
                sub.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
                sub.centerYAnchor.constraint(equalTo: centerYAnchor),
                sub.trailingAnchor.constraint(lessThanOrEqualTo: acc.leadingAnchor, constant: -12),
                acc.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                acc.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }
    }
}
