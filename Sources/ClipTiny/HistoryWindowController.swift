import AppKit
import ApplicationServices

final class ShortcutPanel: NSPanel {
    var focusSearch: (() -> Void)?
    var dismiss: (() -> Void)?
    var copySelection: (() -> Void)?
    var selectKind: ((Int) -> Void)?
    var openLink: (() -> Void)?

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
            default:
                break
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            activateSelection?()
        } else if event.keyCode == 53 { // Esc
            (window as? ShortcutPanel)?.dismiss?()
        } else if event.keyCode == 48 { // Tab
            (window as? ShortcutPanel)?.focusSearch?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class KeycapBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(key: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor

        label.stringValue = key
        label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

final class ColorPreviewCardView: NSView {
    private let swatchBox = NSBox()
    private let hexLabel = NSTextField(labelWithString: "")
    private let rgbLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        swatchBox.boxType = .custom
        swatchBox.titlePosition = .noTitle
        swatchBox.cornerRadius = 10
        swatchBox.borderWidth = 0.5
        swatchBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.4)
        swatchBox.contentViewMargins = .zero

        hexLabel.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        hexLabel.textColor = .labelColor
        hexLabel.isSelectable = true

        rgbLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        rgbLabel.textColor = .secondaryLabelColor
        rgbLabel.isSelectable = true

        let stack = NSStackView(views: [swatchBox, hexLabel, rgbLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            swatchBox.widthAnchor.constraint(equalToConstant: 180),
            swatchBox.heightAnchor.constraint(equalToConstant: 90),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(hex: String, color: NSColor) {
        swatchBox.fillColor = color
        hexLabel.stringValue = hex
        rgbLabel.stringValue = color.rgbComponentsString
    }
}

final class HistoryWindowController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSWindowDelegate,
    NSSearchFieldDelegate {

    private static let windowFrameKey = "HistoryWindowFrame"
    private static let accessibilityPromptedKey = "AccessibilityPermissionPrompted"
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

    private let previewTypeIcon = NSImageView()
    private let previewTitle = NSTextField(labelWithString: "内容预览")
    private let previewSubtitle = NSTextField(labelWithString: "选择一条记录，查看完整内容")
    private let openLinkButton = NSButton(title: "打开链接", target: nil, action: nil)

    private let pasteButton = NSButton(title: "粘贴", target: nil, action: nil)
    private let previewBox = NSBox()
    private let previewImageView = NSImageView()
    private let previewTextView = NSTextView()
    private let previewTextScrollView = NSScrollView()
    private let previewColorCard = ColorPreviewCardView()
    private let previewInfoLabel = NSTextField(labelWithString: "")
    private let previewDetailLabel = NSTextField(labelWithString: "")
    private let previewPlaceholder = NSStackView()
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
        store.onChange = { [weak self] in self?.refresh() }
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
        window?.orderOut(nil)
        searchField.stringValue = ""
        refresh()
        previousApp?.activate()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
    }

    private func restoreWindowFrame() {
        guard let panel = window else { return }
        guard
            let saved = defaults.string(
                forKey: Self.windowFrameKey
            )
        else {
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
        defaults.set(
            NSStringFromRect(frame),
            forKey: Self.windowFrameKey
        )
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
        tableView.activateSelection = { [weak self] in self?.pasteSelectedItem() }
        tableView.setAccessibilityLabel("剪贴板历史记录")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        configureEmptyState(
            listEmptyState, iconView: listEmptyIcon, symbol: "tray", title: listEmptyTitle, detail: listEmptyDetail
        )

        // 右侧预览顶部 Header
        previewTypeIcon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        previewTypeIcon.contentTintColor = .secondaryLabelColor

        previewTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        previewTitle.textColor = .labelColor

        previewSubtitle.font = .systemFont(ofSize: 11)
        previewSubtitle.textColor = .secondaryLabelColor
        previewSubtitle.lineBreakMode = .byTruncatingTail
        previewSubtitle.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        openLinkButton.bezelStyle = .inline
        openLinkButton.controlSize = .small
        openLinkButton.font = .systemFont(ofSize: 10, weight: .medium)
        openLinkButton.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        openLinkButton.imagePosition = .imageTrailing
        openLinkButton.target = self
        openLinkButton.action = #selector(openSelectedItemLink)
        openLinkButton.toolTip = "在默认浏览器中打开 (⌘O)"
        openLinkButton.isHidden = true

        let previewHeaderStack = NSStackView(views: [previewTypeIcon, previewTitle, previewSubtitle])
        previewHeaderStack.orientation = .horizontal
        previewHeaderStack.spacing = 6
        previewHeaderStack.alignment = .centerY

        configurePreview()

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
            shortcutHint("⌘1-3", "筛选")
        ])
        footer.orientation = .horizontal
        footer.spacing = 14

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
         previewHeaderStack, openLinkButton, previewBox, pasteButton, footer, brand,
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

            // 右侧 Header 与左侧 分类选择器 水平基线完全对齐
            previewHeaderStack.leadingAnchor.constraint(equalTo: columnDivider.trailingAnchor, constant: 16),
            previewHeaderStack.centerYAnchor.constraint(equalTo: kindFilter.centerYAnchor),
            previewHeaderStack.trailingAnchor.constraint(lessThanOrEqualTo: openLinkButton.leadingAnchor, constant: -8),

            openLinkButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            openLinkButton.centerYAnchor.constraint(equalTo: kindFilter.centerYAnchor),

            // 右侧 previewBox 顶部和底部与左侧 scrollView 严格对齐
            previewBox.topAnchor.constraint(equalTo: scrollView.topAnchor),
            previewBox.leadingAnchor.constraint(equalTo: columnDivider.trailingAnchor, constant: 14),
            previewBox.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            previewBox.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            bottomDivider.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -42),
            bottomDivider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),

            brand.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            brand.centerYAnchor.constraint(equalTo: surface.bottomAnchor, constant: -21),
            footer.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 20),
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

    private func configurePreview() {
        previewBox.boxType = .custom
        previewBox.titlePosition = .noTitle
        previewBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35)
        previewBox.cornerRadius = 10
        previewBox.borderWidth = 0.5
        previewBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.35)
        previewBox.contentViewMargins = .zero

        previewImageView.imageScaling = .scaleProportionallyDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 8
        previewImageView.layer?.masksToBounds = true
        previewImageView.layer?.borderWidth = 0.5
        previewImageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        [NSLayoutConstraint.Orientation.horizontal, .vertical].forEach {
            previewImageView.setContentHuggingPriority(.init(1), for: $0)
            previewImageView.setContentCompressionResistancePriority(.init(1), for: $0)
        }

        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.drawsBackground = false
        previewTextView.textColor = .textColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        previewTextView.defaultParagraphStyle = paragraph
        previewTextView.textContainerInset = NSSize(width: 6, height: 6)
        previewTextView.minSize = .zero
        previewTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        previewTextView.isVerticallyResizable = true
        previewTextView.isHorizontallyResizable = false
        previewTextView.autoresizingMask = [.width]
        previewTextView.textContainer?.widthTracksTextView = true
        previewTextView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        previewTextView.setAccessibilityLabel("记录全文")

        previewTextScrollView.documentView = previewTextView
        previewTextScrollView.hasVerticalScroller = true
        previewTextScrollView.autohidesScrollers = true
        previewTextScrollView.drawsBackground = false
        previewTextScrollView.borderType = .noBorder

        previewInfoLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        previewInfoLabel.textColor = .secondaryLabelColor
        previewInfoLabel.lineBreakMode = .byTruncatingTail

        previewDetailLabel.font = .systemFont(ofSize: 10)
        previewDetailLabel.textColor = .secondaryLabelColor
        previewDetailLabel.alignment = .right
        previewDetailLabel.lineBreakMode = .byTruncatingTail

        let emptyIcon = NSImageView()
        configureEmptyState(
            previewPlaceholder,
            iconView: emptyIcon,
            symbol: "doc.on.clipboard",
            title: NSTextField(labelWithString: "预览"),
            detail: NSTextField(labelWithString: "选择记录查看完整内容")
        )

        let metadataDivider = NSBox()
        metadataDivider.boxType = .separator

        guard let container = previewBox.contentView else { return }
        [previewImageView, previewTextScrollView, previewColorCard, previewPlaceholder,
         metadataDivider, previewInfoLabel, previewDetailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        NSLayoutConstraint.activate([
            previewInfoLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            previewInfoLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            previewInfoLabel.heightAnchor.constraint(equalToConstant: 14),

            previewDetailLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            previewDetailLabel.centerYAnchor.constraint(equalTo: previewInfoLabel.centerYAnchor),
            previewDetailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: previewInfoLabel.trailingAnchor, constant: 8),

            metadataDivider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            metadataDivider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            metadataDivider.bottomAnchor.constraint(equalTo: previewInfoLabel.topAnchor, constant: -8),

            previewPlaceholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            previewPlaceholder.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -10),
            previewPlaceholder.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -32),

            previewColorCard.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            previewColorCard.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -10),
            previewColorCard.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -24),
            previewColorCard.heightAnchor.constraint(equalToConstant: 160)
        ])

        [previewImageView, previewTextScrollView].forEach {
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                $0.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                $0.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                $0.bottomAnchor.constraint(equalTo: metadataDivider.topAnchor, constant: -8)
            ])
        }
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
            return matchesKind && (query.isEmpty || item.text.localizedCaseInsensitiveContains(query))
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
            pasteSelectedItem()
            return true
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
        cell.configure(item: item, thumbnail: item.isImage ? store.images.thumbnail(for: item.id) : nil)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HistoryRowView()
    }

    private func updatePreview() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else {
            previewPlaceholder.isHidden = false
            previewImageView.isHidden = true
            previewImageView.image = nil
            previewTextScrollView.isHidden = true
            previewColorCard.isHidden = true
            openLinkButton.isHidden = true
            previewTypeIcon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            previewTitle.stringValue = "内容预览"
            previewSubtitle.stringValue = "选择一条记录，查看完整内容"
            previewInfoLabel.stringValue = "选择记录后按回车粘贴"
            previewDetailLabel.stringValue = ""
            pasteButton.isEnabled = false
            return
        }

        let item = filteredItems[row]
        previewPlaceholder.isHidden = true
        pasteButton.isEnabled = true
        previewInfoLabel.stringValue = item.preciseTimestamp
        previewInfoLabel.toolTip = "复制时间：\(item.preciseTimestamp)"

        let kind = detectContentKind(text: item.text, isImage: item.isImage)
        switch kind {
        case .image:
            openLinkButton.isHidden = true
            previewColorCard.isHidden = true
            previewTextScrollView.isHidden = true
            previewImageView.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemPurple
            previewTitle.stringValue = "图片"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(item.sizeSummary)"
            previewDetailLabel.stringValue = "PNG 图像"

            let image = store.images.image(for: item.id)
            previewImageView.image = image
            if image == nil {
                previewInfoLabel.stringValue = "图片文件已丢失，无法预览"
            }

        case .color(let hex, let color):
            openLinkButton.isHidden = true
            previewImageView.isHidden = true
            previewImageView.image = nil
            previewTextScrollView.isHidden = true
            previewColorCard.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemPink
            previewTitle.stringValue = "颜色"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(color.hexRGBString)"
            previewDetailLabel.stringValue = color.rgbComponentsString
            previewColorCard.configure(hex: hex, color: color)

        case .link(let url):
            openLinkButton.isHidden = false
            previewColorCard.isHidden = true
            previewImageView.isHidden = true
            previewImageView.image = nil
            previewTextScrollView.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemTeal
            previewTitle.stringValue = "链接"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(url.host ?? "")"
            previewDetailLabel.stringValue = "\(item.text.count) 字符"

            previewTextView.font = .systemFont(ofSize: 13)
            previewTextView.string = item.text
            previewTextView.scroll(.zero)

        case .code(let lineCount):
            openLinkButton.isHidden = true
            previewColorCard.isHidden = true
            previewImageView.isHidden = true
            previewImageView.image = nil
            previewTextScrollView.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemOrange
            previewTitle.stringValue = "代码"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(lineCount) 行"
            previewDetailLabel.stringValue = "\(item.text.count) 字符"

            previewTextView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            previewTextView.string = item.text
            previewTextView.scroll(.zero)

        case .text:
            openLinkButton.isHidden = true
            previewColorCard.isHidden = true
            previewImageView.isHidden = true
            previewImageView.image = nil
            previewTextScrollView.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .secondaryLabelColor
            previewTitle.stringValue = "文本"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(item.sizeSummary)"
            previewDetailLabel.stringValue = "\(item.text.count) 字符"

            previewTextView.font = .systemFont(ofSize: 13)
            previewTextView.string = item.text
            previewTextView.scroll(.zero)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func relativeDate(_ date: Date) -> String {
        let now = Date()
        guard now.timeIntervalSince(date) >= 60 else { return "刚刚" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    @objc private func activateSelectedItem() {
        pasteSelectedItem()
    }

    private func copySelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        guard writeToPasteboard(filteredItems[row]) else { return }
        hide()
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

    private func pasteSelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        guard writeToPasteboard(filteredItems[row]) else { return }

        hide()

        guard accessibilityAutomationAllowed() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            Self.pasteWhenCursorAvailable(attemptsLeft: 10)
        }
    }

    private static func pasteWhenCursorAvailable(attemptsLeft: Int) {
        let status = focusedElementTextStatus()
        switch status {
        case .textInput:
            postPasteShortcut()
        case .nonText, .unavailable:
            guard attemptsLeft > 1 else {
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if case .unavailable = status,
                   frontmostPID != ProcessInfo.processInfo.processIdentifier {
                    postPasteShortcut()
                }
                return
            }
            retryPaste(attemptsLeft: attemptsLeft)
        }
    }

    private static func retryPaste(attemptsLeft: Int) {
        guard attemptsLeft > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pasteWhenCursorAvailable(attemptsLeft: attemptsLeft - 1)
        }
    }

    private func writeToPasteboard(_ item: HistoryItem) -> Bool {
        let pasteboard = NSPasteboard.general
        switch item.kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(item.text, forType: .string)
        case .image:
            guard let png = store.images.pngData(for: item.id) else { return false }
            pasteboard.declareTypes([.png, .tiff], owner: nil)
            pasteboard.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
        onPasteboardWrite?(pasteboard.changeCount)
        return true
    }

    private enum FocusedElementTextStatus {
        case textInput
        case nonText
        case unavailable
    }

    private static func focusedElementTextStatus() -> FocusedElementTextStatus {
        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(),
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success,
            let value = focused,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return .unavailable }

        let element = value as! AXUIElement

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return .textInput
        }

        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success {
            return .textInput
        }

        var role: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXRoleAttribute as CFString,
                &role
            ) == .success,
            let name = role as? String
        else { return .unavailable }
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(name) {
            return .textInput
        }

        let nonTextRoles: Set<String> = [
            "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem",
            "AXStaticText", "AXImage", "AXList", "AXTable", "AXOutline",
            "AXBrowser", "AXScrollArea", "AXToolbar", "AXWindow", "AXSheet",
            "AXDialog", "AXDesktop", "AXSplitGroup"
        ]
        return nonTextRoles.contains(name) ? .nonText : .unavailable
    }

    private static func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: true
        ),
              let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: false
        ) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func accessibilityAutomationAllowed() -> Bool {
        if AXIsProcessTrusted() { return true }
        guard !defaults.bool(forKey: Self.accessibilityPromptedKey) else {
            return false
        }

        defaults.set(true, forKey: Self.accessibilityPromptedKey)
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
