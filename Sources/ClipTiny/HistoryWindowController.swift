import AppKit
import ApplicationServices

enum WindowPositionMode: String, CaseIterable {
    case centerAndRemember = "remember"
    case followMouse = "mouse"
    case followFocusedElement = "cursor"
}

final class ShortcutPanel: NSPanel {
    var focusSearch: (() -> Void)?
    var dismiss: (() -> Void)?
    var copySelection: (() -> Void)?
    var selectKind: ((Int) -> Void)?
    var openLink: (() -> Void)?
    var revealFile: (() -> Void)?
    var togglePin: (() -> Void)?
    var deleteSelection: (() -> Void)?
    var pastePlainText: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let shortcutModifiers = event.modifierFlags.intersection([
            .command, .option, .control, .shift
        ])

        if shortcutModifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f":
                focusSearch?()
                return true
            case "w":
                dismiss?()
                return true
            case "c":
                copySelection?()
                return true
            case "1":
                selectKind?(0)
                return true
            case "2":
                selectKind?(1)
                return true
            case "3":
                selectKind?(2)
                return true
            case "o":
                openLink?()
                return true
            case "r":
                revealFile?()
                return true
            case "p":
                togglePin?()
                return true
            default:
                break
            }

            if event.keyCode == 51 { // Command + Backspace
                deleteSelection?()
                return true
            }
        } else if shortcutModifiers == .option {
            if event.keyCode == 36 || event.keyCode == 76 { // Option + Enter
                pastePlainText?()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss?()
    }
}

final class KeyboardTableView: NSTableView {
    var activateSelection: (() -> Void)?
    var pastePlainText: (() -> Void)?
    var deleteSelection: (() -> Void)?
    var togglePin: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            if event.modifierFlags.contains(.option) {
                pastePlainText?()
            } else {
                activateSelection?()
            }
        } else if event.keyCode == 53 { // Esc
            (window as? ShortcutPanel)?.dismiss?()
        } else if event.keyCode == 48 { // Tab
            (window as? ShortcutPanel)?.focusSearch?()
        } else if (event.keyCode == 51 && event.modifierFlags.contains(.command)) || event.keyCode == 117 {
            deleteSelection?()
        } else if event.charactersIgnoringModifiers?.lowercased() == "p" && event.modifierFlags.contains(.command) {
            togglePin?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class KeycapButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        contentTintColor = .secondaryLabelColor
        alignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.6).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
    }
}

final class HistoryWindowController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSWindowDelegate,
    NSSearchFieldDelegate {

    private static let windowFrameKey = "HistoryWindowFrame"
    private static let windowPositionModeKey = "WindowPositionMode"
    private static let minimumSize = NSSize(width: 760, height: 440)

    private let defaults: UserDefaults
    private let store: HistoryStore
    private let searchField = NSSearchField()
    private let searchIcon = NSImageView()
    private let closeButton = KeycapButton(title: "esc", target: nil, action: nil)
    private let tableView = KeyboardTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let kindFilter = NSSegmentedControl(
        labels: ["全部", "文本", "图片"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let listEmptyState = NSStackView()
    private let listEmptyIcon = NSImageView()
    private let listEmptyTitle = NSTextField(labelWithString: "还没有复制记录")
    private let listEmptyDetail = NSTextField(labelWithString: "复制文本或图片后，会显示在这里")

    private let previewView = HistoryPreviewCardView()
    private let pasteButton = NSButton(title: "粘贴", target: nil, action: nil)

    private var filteredItems: [HistoryItem] = []
    private var previousApp: NSRunningApplication?

    /// 写回剪贴板后回调，用于让 `ClipboardMonitor` 跳过这次自己造成的变化。
    var onPasteboardWrite: ((Int) -> Void)?

    init(store: HistoryStore, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.store = store

        let panel = ShortcutPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.minimumSize.width + 100,
                height: Self.minimumSize.height + 80
            ),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClipTiny · 剪贴板历史"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach {
            panel.standardWindowButton($0)?.isHidden = true
        }
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.minSize = Self.minimumSize

        super.init(window: panel)
        panel.delegate = self
        configureUI()
        restoreWindowFrame()
        refresh()

        panel.focusSearch = { [weak self] in self?.focusSearch() }
        panel.dismiss = { [weak self] in self?.hide() }
        panel.copySelection = { [weak self] in self?.copySelectedItem() }
        panel.selectKind = { [weak self] index in self?.selectKindFilter(index) }
        panel.openLink = { [weak self] in self?.openSelectedItemLink() }
        panel.revealFile = { [weak self] in self?.revealSelectedItemInFinder() }
        panel.togglePin = { [weak self] in self?.togglePinSelectedItem() }
        panel.deleteSelection = { [weak self] in self?.deleteSelectedItem() }
        panel.pastePlainText = { [weak self] in self?.pasteSelectedItem(plainText: true) }

        previewView.onOpenLink = { [weak self] in self?.openSelectedItemLink() }
        previewView.onRevealInFinder = { [weak self] in self?.revealSelectedItemInFinder() }
        store.onChange = { [weak self] in self?.refresh() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        positionWindow()
        refresh()

        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        focusSearch()
    }

    func hide() {
        saveWindowFrame()
        store.flushSync()
        window?.orderOut(nil)
        searchField.stringValue = ""
        refresh()
        previousApp?.activate()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
        store.flushSync()
    }

    private func positionWindow() {
        guard let panel = window else { return }
        let modeString = defaults.string(forKey: Self.windowPositionModeKey)
            ?? WindowPositionMode.centerAndRemember.rawValue
        let mode = WindowPositionMode(rawValue: modeString) ?? .centerAndRemember

        switch mode {
        case .centerAndRemember:
            // 记忆模式下只在初始时恢复，后续保持当前位置
            break
        case .followMouse:
            positionNearMouse(panel: panel)
        case .followFocusedElement:
            if !positionNearFocusedElement(panel: panel) {
                positionNearMouse(panel: panel)
            }
        }
    }

    private func positionNearMouse(panel: NSWindow) {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSPointInRect(mouseLoc, $0.frame) }
            ?? NSScreen.main ?? panel.screen
        guard let screen else { return }
        let vis = screen.visibleFrame
        let size = panel.frame.size
        var x = mouseLoc.x - size.width * 0.3
        var y = mouseLoc.y - size.height * 0.1
        x = max(vis.minX + 10, min(x, vis.maxX - size.width - 10))
        y = max(vis.minY + 10, min(y, vis.maxY - size.height - 10))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionNearFocusedElement(panel: NSWindow) -> Bool {
        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(),
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success,
            let value = focused,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }

        let element = value as! AXUIElement
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?

        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
            let posAX = posVal, let sizeAX = sizeVal
        else { return false }

        var screenPoint = CGPoint.zero
        var elemSize = CGSize.zero
        guard
            AXValueGetValue(posAX as! AXValue, .cgPoint, &screenPoint),
            AXValueGetValue(sizeAX as! AXValue, .cgSize, &elemSize)
        else { return false }

        guard let primary = NSScreen.screens.first else { return false }
        let primaryHeight = primary.frame.height
        let cocoaY = primaryHeight - (screenPoint.y + elemSize.height)

        let targetScreen = NSScreen.screens.first {
            NSPointInRect(NSPoint(x: screenPoint.x, y: cocoaY), $0.frame)
        } ?? primary

        let vis = targetScreen.visibleFrame
        let size = panel.frame.size
        var x = screenPoint.x
        var y = cocoaY - size.height - 10
        if y < vis.minY {
            y = (primaryHeight - screenPoint.y) + 10
        }

        x = max(vis.minX + 10, min(x, vis.maxX - size.width - 10))
        y = max(vis.minY + 10, min(y, vis.maxY - size.height - 10))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        return true
    }

    private func restoreWindowFrame() {
        guard let panel = window else { return }
        guard let saved = defaults.string(forKey: Self.windowFrameKey) else {
            panel.center()
            return
        }

        let savedFrame = NSRectFromString(saved)
        let frame = NSRect(
            x: savedFrame.origin.x,
            y: savedFrame.origin.y,
            width: max(savedFrame.width, Self.minimumSize.width),
            height: max(savedFrame.height, Self.minimumSize.height)
        )
        let isVisible = NSScreen.screens.contains {
            $0.visibleFrame.intersects(frame)
        }
        if isVisible {
            panel.setFrame(frame, display: false)
        } else {
            panel.center()
        }
    }

    private func saveWindowFrame() {
        guard let frame = window?.frame else { return }
        defaults.set(NSStringFromRect(frame), forKey: Self.windowFrameKey)
    }

    private func configureUI() {
        guard let contentView = window?.contentView else { return }

        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 22
        let surface = NSView()
        glass.contentView = surface
        glass.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: contentView.topAnchor),
            glass.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        searchField.placeholderString = "搜索剪贴板…"
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 18, weight: .regular)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.setAccessibilityLabel("搜索剪贴板历史")

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        searchIcon.contentTintColor = .secondaryLabelColor

        closeButton.target = self
        closeButton.action = #selector(closeHistory)
        closeButton.toolTip = "关闭历史窗口 (Esc)"
        closeButton.setAccessibilityLabel("关闭历史窗口")

        kindFilter.selectedSegment = 0
        kindFilter.segmentStyle = .capsule
        kindFilter.segmentDistribution = .fillEqually
        kindFilter.controlSize = .small
        kindFilter.font = .systemFont(ofSize: 11, weight: .medium)
        kindFilter.target = self
        kindFilter.action = #selector(changeKindFilter)
        kindFilter.setAccessibilityLabel("记录类型")

        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = 56
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(activateSelectedItem)
        tableView.activateSelection = { [weak self] in self?.pasteSelectedItem(plainText: false) }
        tableView.pastePlainText = { [weak self] in self?.pasteSelectedItem(plainText: true) }
        tableView.deleteSelection = { [weak self] in self?.deleteSelectedItem() }
        tableView.togglePin = { [weak self] in self?.togglePinSelectedItem() }
        tableView.setAccessibilityLabel("剪贴板历史记录")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        configureEmptyState(
            listEmptyState, iconView: listEmptyIcon, symbol: "tray", title: listEmptyTitle, detail: listEmptyDetail
        )

        pasteButton.bezelStyle = .rounded
        pasteButton.controlSize = .small
        pasteButton.font = .systemFont(ofSize: 11, weight: .medium)
        pasteButton.image = NSImage(systemSymbolName: "return", accessibilityDescription: nil)
        pasteButton.imagePosition = .imageTrailing
        pasteButton.target = self
        pasteButton.action = #selector(activateSelectedItem)
        pasteButton.toolTip = "粘贴到刚才的应用（回车）"
        pasteButton.contentTintColor = .controlAccentColor

        let footer = NSStackView(views: [
            shortcutHint("↑↓", "选择"),
            shortcutHint("⌘F", "搜索"),
            shortcutHint("⌘C", "复制"),
            shortcutHint("⌘P", "置顶"),
            shortcutHint("⌘⌫", "删除")
        ])
        footer.orientation = .horizontal
        footer.spacing = 12

        let brand = NSTextField(labelWithString: "ClipTiny")
        brand.font = .systemFont(ofSize: 11, weight: .semibold)
        brand.textColor = .secondaryLabelColor

        let listRegion = NSLayoutGuide()
        surface.addLayoutGuide(listRegion)

        let topDivider = NSBox()
        let columnDivider = NSBox()
        let bottomDivider = NSBox()
        [topDivider, columnDivider, bottomDivider].forEach { $0.boxType = .separator }

        [searchIcon, searchField, closeButton, kindFilter, countLabel, scrollView, listEmptyState,
         previewView, pasteButton, footer, brand,
         topDivider, columnDivider, bottomDivider].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview($0)
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: surface.topAnchor, constant: 18),
            searchIcon.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            searchIcon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 34),

            closeButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -22),
            closeButton.widthAnchor.constraint(equalToConstant: 38),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            topDivider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),
            topDivider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),

            listRegion.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            listRegion.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            listRegion.widthAnchor.constraint(equalTo: surface.widthAnchor, multiplier: 0.54),
            listRegion.heightAnchor.constraint(equalToConstant: 0),

            columnDivider.leadingAnchor.constraint(equalTo: listRegion.trailingAnchor),
            columnDivider.widthAnchor.constraint(equalToConstant: 1),
            columnDivider.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            columnDivider.bottomAnchor.constraint(equalTo: bottomDivider.topAnchor),

            kindFilter.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            kindFilter.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 12),
            kindFilter.widthAnchor.constraint(equalToConstant: 180),
            kindFilter.heightAnchor.constraint(equalToConstant: 24),

            countLabel.centerYAnchor.constraint(equalTo: kindFilter.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: columnDivider.leadingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: kindFilter.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: columnDivider.leadingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: bottomDivider.topAnchor, constant: -8),

            listEmptyState.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            listEmptyState.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            listEmptyState.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -24),

            previewView.topAnchor.constraint(equalTo: kindFilter.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: columnDivider.trailingAnchor, constant: 14),
            previewView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            previewView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            bottomDivider.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -42),
            bottomDivider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),

            brand.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            brand.centerYAnchor.constraint(equalTo: surface.bottomAnchor, constant: -21),
            footer.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 16),
            footer.centerYAnchor.constraint(equalTo: brand.centerYAnchor),

            pasteButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            pasteButton.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            pasteButton.widthAnchor.constraint(equalToConstant: 76)
        ])
    }

    @objc private func closeHistory() {
        hide()
    }

    private func shortcutHint(_ key: String, _ title: String) -> NSView {
        let keyBadge = KeycapBadgeView(key: key)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [keyBadge, titleLabel])
        stack.spacing = 5
        stack.alignment = .centerY
        return stack
    }

    private func configureEmptyState(
        _ stack: NSStackView,
        iconView: NSImageView,
        symbol: String,
        title: NSTextField,
        detail: NSTextField
    ) {
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 30, weight: .light)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 40).isActive = true

        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = .secondaryLabelColor

        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byWordWrapping

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        [iconView, title, detail].forEach { stack.addArrangedSubview($0) }
    }

    private func refresh() {
        let selectedID = filteredItems.indices.contains(tableView.selectedRow)
            ? filteredItems[tableView.selectedRow].id
            : nil

        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        filteredItems = store.items.filter { item in
            let matchesKind = kindFilter.selectedSegment == 0
                || (kindFilter.selectedSegment == 1 && !item.isImage)
                || (kindFilter.selectedSegment == 2 && item.isImage)
            guard matchesKind else { return false }
            guard !query.isEmpty else { return true }
            return PinyinHelper.queryMatches(query, text: item.text)
        }
        countLabel.stringValue = "\(filteredItems.count) 条"
        listEmptyState.isHidden = !filteredItems.isEmpty

        if !query.isEmpty {
            listEmptyIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            listEmptyTitle.stringValue = "没有找到相关记录"
            listEmptyDetail.stringValue = "换个关键词，或试试其他类型"
        } else {
            listEmptyIcon.image = NSImage(systemSymbolName: "tray", accessibilityDescription: nil)
            listEmptyTitle.stringValue = kindFilter.selectedSegment == 0
                ? "还没有复制记录" : "暂无\(kindFilter.label(forSegment: kindFilter.selectedSegment) ?? "")记录"
            listEmptyDetail.stringValue = "复制文本或图片后，会显示在这里"
        }
        tableView.reloadData()

        if let selectedID,
           let index = filteredItems.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updatePreview()
    }

    private func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === searchField, !textView.hasMarkedText() else { return false }
        switch NSStringFromSelector(commandSelector) {
        case "moveDown:", "moveUp:":
            guard !filteredItems.isEmpty else { return true }
            let offset = NSStringFromSelector(commandSelector) == "moveDown:" ? 1 : -1
            let row = min(max(tableView.selectedRow + offset, 0), filteredItems.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return true
        case "pageDown:":
            guard !filteredItems.isEmpty else { return true }
            let row = min(max(tableView.selectedRow + 6, 0), filteredItems.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return true
        case "pageUp:":
            guard !filteredItems.isEmpty else { return true }
            let row = min(max(tableView.selectedRow - 6, 0), filteredItems.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return true
        case "insertNewline:":
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                pasteSelectedItem(plainText: true)
            } else {
                pasteSelectedItem(plainText: false)
            }
            return true
        case "deleteBackward:":
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                deleteSelectedItem()
                return true
            }
            return false
        case "cancelOperation:":
            if !searchField.stringValue.isEmpty {
                searchField.stringValue = ""
                refresh()
            } else {
                hide()
            }
            return true
        case "insertTab:":
            if !filteredItems.isEmpty {
                window?.makeFirstResponder(tableView)
                return true
            }
            return false
        default:
            return false
        }
    }

    @objc private func changeKindFilter() {
        refresh()
    }

    private func selectKindFilter(_ index: Int) {
        guard index >= 0 && index < kindFilter.segmentCount else { return }
        kindFilter.selectedSegment = index
        refresh()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HistoryCellView
            ?? HistoryCellView()
        cell.identifier = identifier
        let item = filteredItems[row]
        cell.configure(
            item: item,
            thumbnail: item.isImage ? store.images.thumbnail(for: item.id) : nil
        )
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("HistoryRow")
        let rowView = (tableView.makeView(withIdentifier: identifier, owner: self) as? HistoryRowView)
            ?? HistoryRowView()
        rowView.identifier = identifier
        return rowView
    }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView as? HistoryRowView)?.updateHoverState()
        }
    }

    private func updatePreview() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else {
            previewView.showEmptyState()
            pasteButton.isEnabled = false
            return
        }
        pasteButton.isEnabled = true
        let item = filteredItems[row]
        previewView.display(item: item, images: store.images)
    }

    @objc private func activateSelectedItem() {
        pasteSelectedItem(plainText: false)
    }

    private func copySelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        guard writeToPasteboard(filteredItems[row], plainText: false) else { return }
        hide()
    }

    private func deleteSelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let item = filteredItems[row]
        store.delete(id: item.id)

        filteredItems.remove(at: row)
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade)

        if !filteredItems.isEmpty {
            let nextRow = min(row, filteredItems.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        countLabel.stringValue = "\(filteredItems.count) 条"
        listEmptyState.isHidden = !filteredItems.isEmpty
        updatePreview()
    }

    private func togglePinSelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let item = filteredItems[row]
        store.togglePin(id: item.id)
        refresh()
    }

    @objc private func openSelectedItemLink() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let trimmed = filteredItems[row].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            hide()
        }
    }

    @objc private func revealSelectedItemInFinder() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let item = filteredItems[row]
        if let url = item.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            hide()
        }
    }

    private func pasteSelectedItem(plainText: Bool = false) {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        guard writeToPasteboard(filteredItems[row], plainText: plainText) else { return }

        hide()

        guard PasteService.accessibilityAutomationAllowed(defaults: defaults) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            PasteService.pasteWhenCursorAvailable(attemptsLeft: 10)
        }
    }

    private func writeToPasteboard(_ item: HistoryItem, plainText: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if plainText {
            let cleanedText = PasteService.formatPlainText(item.text)
            pasteboard.setString(cleanedText, forType: .string)
            onPasteboardWrite?(pasteboard.changeCount)
            return true
        }

        switch item.kind {
        case .text:
            pasteboard.setString(item.text, forType: .string)
        case .image:
            guard let png = store.images.pngData(for: item.id) else { return false }
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            pasteboard.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        case .file:
            if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
                pasteboard.setString(url.path, forType: .string)
            } else {
                pasteboard.setString(item.text, forType: .string)
            }
        }
        onPasteboardWrite?(pasteboard.changeCount)
        return true
    }
}
