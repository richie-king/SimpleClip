import AppKit
import ApplicationServices

enum WindowPositionMode: String, CaseIterable {
    case centerAndRemember = "remember"
    case followMouse = "mouse"
    case followFocusedElement = "cursor"
}

final class ShortcutPanel: NSPanel {
    weak var controller: HistoryWindowController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let shortcutModifiers = event.modifierFlags.intersection([
            .command, .option, .control, .shift
        ])

        if shortcutModifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "f":
                controller?.focusSearch()
                return true
            case "w":
                controller?.hide()
                return true
            case "c":
                if controller?.isSearchFieldFocusedWithSelection == true {
                    return false
                }
                controller?.copySelectedItem()
                return true
            case "1", "2", "3":
                if let num = Int(key) {
                    controller?.selectKindFilter(num - 1)
                    return true
                }
            case "o":
                controller?.openSelectedItemLink()
                return true
            case "r":
                controller?.revealSelectedItemInFinder()
                return true
            case "p":
                controller?.togglePinSelectedItem()
                return true
            default:
                break
            }

            if event.keyCode == 51 { // Command + Backspace
                if controller?.isSearchFieldFocusedWithText == true || controller?.isSearchFieldComposingText == true {
                    return false
                }
                controller?.deleteSelectedItem()
                return true
            }
        } else if shortcutModifiers == .option {
            if event.keyCode == 36 || event.keyCode == 76 { // Option + Enter
                controller?.pasteSelectedItem(plainText: true)
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.hide()
    }
}

final class KeyboardTableView: NSTableView {
    var activateSelection: (() -> Void)?
    var pastePlainText: (() -> Void)?
    var deleteSelection: (() -> Void)?

    private var mouseTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        mouseTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard window?.isVisible == true else { return }
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0 && row < numberOfRows && row != selectedRow {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            if event.modifierFlags.contains(.option) {
                pastePlainText?()
            } else {
                activateSelection?()
            }
        } else if event.keyCode == 53 { // Esc
            (window as? ShortcutPanel)?.controller?.hide()
        } else if event.keyCode == 48 { // Tab
            (window as? ShortcutPanel)?.controller?.focusSearch()
        } else if event.keyCode == 117 { // Forward Delete
            deleteSelection?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class KeycapBadgeView: NSView {
    let key: String
    let tintColor: NSColor?

    private let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)

    init(key: String, tint: NSColor? = nil) {
        self.key = key
        self.tintColor = tint
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let size = (key as NSString).size(withAttributes: [.font: font])
        let width = max(20.0, ceil(size.width) + 10.0)
        return NSSize(width: width, height: 18.0)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgPath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
            xRadius: 4.5,
            yRadius: 4.5
        )
        NSColor.controlBackgroundColor.withAlphaComponent(0.70).setFill()
        bgPath.fill()

        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        bgPath.lineWidth = 0.5
        bgPath.stroke()

        let color = tintColor ?? NSColor.labelColor.withAlphaComponent(0.85)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let textSize = (key as NSString).size(withAttributes: attrs)
        let x = round((bounds.width - textSize.width) / 2.0)
        let y = round((bounds.height - textSize.height) / 2.0)
        (key as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
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
    private let closeButton = NSButton(title: "esc", target: nil, action: nil)
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
    private var isDeletingSelectedItem = false

    private var searchEditor: NSTextView? {
        searchField.currentEditor() as? NSTextView
    }

    var isSearchFieldFocused: Bool {
        searchEditor != nil || window?.firstResponder === searchField
    }

    var isSearchFieldFocusedWithText: Bool {
        isSearchFieldFocused && !searchField.stringValue.isEmpty
    }

    var isSearchFieldFocusedWithSelection: Bool {
        (searchEditor?.selectedRange().length ?? 0) > 0
    }

    var isSearchFieldComposingText: Bool {
        searchEditor?.hasMarkedText() ?? false
    }

    func clearSearchField() {
        searchField.stringValue = ""
        if let editor = searchField.currentEditor() as? NSTextView {
            editor.string = ""
        }
        refresh()
    }

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

        panel.controller = self

        previewView.onOpenLink = { [weak self] in self?.openSelectedItemLink() }
        previewView.onRevealInFinder = { [weak self] in self?.revealSelectedItemInFinder() }
        store.onChange = { [weak self] in
            guard let self, !self.isDeletingSelectedItem else { return }
            self.refresh()
        }
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
        clearSearchField()
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
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(savedFrame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { panel.center(); return }

        let vis = screen.visibleFrame
        let width = min(max(savedFrame.width, Self.minimumSize.width), vis.width - 40, 1200)
        let height = min(max(savedFrame.height, Self.minimumSize.height), vis.height - 40, 800)
        let x = max(vis.minX + 10, min(savedFrame.origin.x, vis.maxX - width - 10))
        let y = max(vis.minY + 10, min(savedFrame.origin.y, vis.maxY - height - 10))

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
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
        searchField.font = .systemFont(ofSize: 17, weight: .regular)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.setAccessibilityLabel("搜索剪贴板历史")

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        searchIcon.contentTintColor = .secondaryLabelColor

        closeButton.bezelStyle = .inline
        closeButton.controlSize = .small
        closeButton.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .semibold)
        closeButton.imagePosition = .imageLeading
        closeButton.target = self
        closeButton.action = #selector(closeHistory)
        closeButton.toolTip = "关闭历史窗口 (Esc)"
        closeButton.setAccessibilityLabel("关闭历史窗口")
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 5.5
        closeButton.layer?.masksToBounds = true
        closeButton.layer?.borderWidth = 0.5
        closeButton.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        closeButton.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
        closeButton.contentTintColor = .secondaryLabelColor

        kindFilter.selectedSegment = 0
        kindFilter.segmentStyle = .capsule
        kindFilter.segmentDistribution = .fillEqually
        kindFilter.controlSize = .small
        kindFilter.font = .systemFont(ofSize: 11.5, weight: .medium)
        kindFilter.target = self
        kindFilter.action = #selector(changeKindFilter)
        kindFilter.setAccessibilityLabel("记录类型")

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = 58
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(tableViewClicked)
        tableView.doubleAction = #selector(activateSelectedItem)
        tableView.activateSelection = { [weak self] in self?.pasteSelectedItem(plainText: false) }
        tableView.pastePlainText = { [weak self] in self?.pasteSelectedItem(plainText: true) }
        tableView.deleteSelection = { [weak self] in self?.deleteSelectedItem() }
        tableView.setAccessibilityLabel("剪贴板历史记录")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)
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
        pasteButton.font = .systemFont(ofSize: 11.5, weight: .semibold)
        pasteButton.image = NSImage(systemSymbolName: "return", accessibilityDescription: nil)
        pasteButton.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        pasteButton.imagePosition = .imageTrailing
        pasteButton.target = self
        pasteButton.action = #selector(activateSelectedItem)
        pasteButton.toolTip = "粘贴到刚才的应用（回车）"
        pasteButton.contentTintColor = .controlAccentColor

        let footer = NSStackView(views: [
            shortcutHint("↑↓", "选择"),
            shortcutHint("⌘F", "搜索"),
            shortcutHint("⌘C", "复制"),
            shortcutHint("⌘P", "置顶", tint: .systemOrange),
            shortcutHint("⌘⌫", "删除")
        ])
        footer.orientation = .horizontal
        footer.spacing = 14
        footer.alignment = .centerY

        let brand = NSTextField(labelWithString: "ClipTiny")
        brand.font = .systemFont(ofSize: 11.5, weight: .semibold)
        brand.textColor = .tertiaryLabelColor

        let listRegion = NSLayoutGuide()
        surface.addLayoutGuide(listRegion)

        let topDivider = makeDivider()
        let columnDivider = makeDivider()
        let bottomDivider = makeDivider()

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
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            topDivider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),
            topDivider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

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
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),

            brand.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            brand.centerYAnchor.constraint(equalTo: surface.bottomAnchor, constant: -21),
            footer.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 16),
            footer.centerYAnchor.constraint(equalTo: brand.centerYAnchor),

            pasteButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            pasteButton.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            pasteButton.widthAnchor.constraint(equalToConstant: 76)
        ])
    }

    private func makeDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.fillColor = NSColor.separatorColor.withAlphaComponent(0.28)
        return box
    }

    @objc private func closeHistory() {
        hide()
    }

    @objc private func tableViewClicked() {
        focusSearch()
    }

    private func shortcutHint(_ key: String, _ title: String, tint: NSColor? = nil) -> NSView {
        let keyBadge = KeycapBadgeView(key: key, tint: tint)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [keyBadge, titleLabel])
        stack.orientation = .horizontal
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

        updateEmptyStateContent(query: query)
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

    private func updateEmptyStateContent(query: String) {
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
    }

    fileprivate func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    private func stepRow(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let row = min(max(tableView.selectedRow + offset, 0), filteredItems.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === searchField, !textView.hasMarkedText() else { return false }
        switch NSStringFromSelector(commandSelector) {
        case "moveDown:":
            stepRow(by: 1); return true
        case "moveUp:":
            stepRow(by: -1); return true
        case "pageDown:":
            stepRow(by: 6); return true
        case "pageUp:":
            stepRow(by: -6); return true
        case "insertNewline:":
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                pasteSelectedItem(plainText: true)
            } else {
                pasteSelectedItem(plainText: false)
            }
            return true
        case "deleteToBeginningOfLine:", "deleteToBeginningOfParagraph:":
            guard !searchField.stringValue.isEmpty else { return false }
            clearSearchField()
            return true
        case "deleteBackward:":
            guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return false }
            if !searchField.stringValue.isEmpty {
                clearSearchField()
            } else {
                deleteSelectedItem()
            }
            return true
        case "cancelOperation:":
            if !searchField.stringValue.isEmpty {
                clearSearchField()
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

    fileprivate func selectKindFilter(_ index: Int) {
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

    fileprivate func copySelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        guard writeToPasteboard(filteredItems[row], plainText: false) else { return }
        hide()
    }

    fileprivate func deleteSelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let item = filteredItems[row]

        isDeletingSelectedItem = true
        defer { isDeletingSelectedItem = false }

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
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updateEmptyStateContent(query: query)
        listEmptyState.isHidden = !filteredItems.isEmpty
        updatePreview()
    }

    fileprivate func togglePinSelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let item = filteredItems[row]
        store.togglePin(id: item.id)
        refresh()
    }

    @objc fileprivate func openSelectedItemLink() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let trimmed = filteredItems[row].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            hide()
        }
    }

    @objc fileprivate func revealSelectedItemInFinder() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        let item = filteredItems[row]
        if let url = item.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            hide()
        }
    }

    fileprivate func pasteSelectedItem(plainText: Bool = false) {
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
