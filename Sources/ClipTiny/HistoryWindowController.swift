import AppKit
import ApplicationServices

final class ShortcutPanel: NSPanel {
    var focusSearch: (() -> Void)?
    var dismiss: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            focusSearch?()
            return true
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
        if event.keyCode == 36 || event.keyCode == 76 {
            activateSelection?()
        } else {
            super.keyDown(with: event)
        }
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

    private let store: HistoryStore
    private let searchField = NSSearchField()
    private let tableView = KeyboardTableView()
    private let countLabel = NSTextField(labelWithString: "")
    private let previewBox = NSBox()
    private let previewImageView = NSImageView()
    private let previewTextView = NSTextView()
    private let previewTextScrollView = NSScrollView()
    private let previewInfoLabel = NSTextField(labelWithString: "")
    private let previewPlaceholder = NSTextField(labelWithString: "选中记录后在这里预览")
    private var filteredItems: [HistoryItem] = []
    private var previousApp: NSRunningApplication?

    /// 写回剪贴板后回调，用于让 `ClipboardMonitor` 跳过这次自己造成的变化。
    var onPasteboardWrite: ((Int) -> Void)?

    init(store: HistoryStore) {
        self.store = store

        let panel = ShortcutPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Self.minimumSize.width + 120,
                height: Self.minimumSize.height + 80
            ),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "剪贴板历史"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
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

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if filteredItems.isEmpty {
            focusSearch()
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            window?.makeFirstResponder(tableView)
        }
    }

    func hide() {
        saveWindowFrame()
        window?.orderOut(nil)
        searchField.stringValue = ""
        refresh()
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame()
    }

    private func restoreWindowFrame() {
        guard let panel = window else { return }
        guard
            let saved = UserDefaults.standard.string(
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
        UserDefaults.standard.set(
            NSStringFromRect(frame),
            forKey: Self.windowFrameKey
        )
    }

    private func configureUI() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "剪贴板历史")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right

        searchField.placeholderString = "搜索粘贴记录"
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 58
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(activateSelectedItem)
        tableView.activateSelection = { [weak self] in self?.pasteSelectedItem() }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let hint = NSTextField(labelWithString: "↑↓ 选择    ↩ 粘贴    ⌘F 搜索    esc 关闭")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor

        configurePreview()

        [title, countLabel, searchField, scrollView, previewBox, hint].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            countLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            searchField.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.46),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -10),

            previewBox.topAnchor.constraint(equalTo: scrollView.topAnchor),
            previewBox.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            previewBox.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 12),
            previewBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            hint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            hint.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    private func configurePreview() {
        previewBox.boxType = .custom
        previewBox.titlePosition = .noTitle
        previewBox.fillColor = .underPageBackgroundColor
        previewBox.borderColor = .separatorColor
        previewBox.borderWidth = 1
        previewBox.cornerRadius = 10
        previewBox.contentViewMargins = .zero

        previewImageView.imageScaling = .scaleProportionallyDown
        previewImageView.imageAlignment = .alignCenter
        // NSImageView 的固有尺寸就是图片尺寸，不压下去的话大图会把窗口撑大。
        [NSLayoutConstraint.Orientation.horizontal, .vertical].forEach {
            previewImageView.setContentHuggingPriority(.init(1), for: $0)
            previewImageView.setContentCompressionResistancePriority(.init(1), for: $0)
        }

        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.drawsBackground = false
        previewTextView.font = .systemFont(ofSize: 13)
        previewTextView.textContainerInset = NSSize(width: 4, height: 4)
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

        previewTextScrollView.documentView = previewTextView
        previewTextScrollView.hasVerticalScroller = true
        previewTextScrollView.autohidesScrollers = true
        previewTextScrollView.drawsBackground = false

        previewInfoLabel.font = .systemFont(ofSize: 11)
        previewInfoLabel.textColor = .secondaryLabelColor
        previewInfoLabel.lineBreakMode = .byTruncatingTail
        // 只放松横向，纵向要保住这一行的高度。
        previewInfoLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        previewPlaceholder.font = .systemFont(ofSize: 12)
        previewPlaceholder.textColor = .tertiaryLabelColor

        guard let container = previewBox.contentView else { return }
        [previewImageView, previewTextScrollView, previewPlaceholder, previewInfoLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        NSLayoutConstraint.activate([
            previewInfoLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            previewInfoLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            previewInfoLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            previewPlaceholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            previewPlaceholder.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        [previewImageView, previewTextScrollView].forEach {
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                $0.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                $0.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                $0.bottomAnchor.constraint(equalTo: previewInfoLabel.topAnchor, constant: -10)
            ])
        }
    }

    private func refresh() {
        // 窗口开着时复制了新内容，不要把用户选中的那条弄丢。
        let selectedID = filteredItems.indices.contains(tableView.selectedRow)
            ? filteredItems[tableView.selectedRow].id
            : nil

        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredItems = store.items
        } else {
            filteredItems = store.items.filter {
                $0.text.localizedCaseInsensitiveContains(query)
            }
        }
        countLabel.stringValue = "\(filteredItems.count) / \(store.items.count)"
        tableView.reloadData()

        if let selectedID,
           let index = filteredItems.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updatePreview()
    }

    private func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_ obj: Notification) {
        refresh()
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
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
        let cell: NSTableCellView
        let icon: NSImageView
        let preview: NSTextField
        let detail: NSTextField

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self)
            as? NSTableCellView,
           let iconView = reused.viewWithTag(3) as? NSImageView,
           let previewField = reused.viewWithTag(1) as? NSTextField,
           let detailField = reused.viewWithTag(2) as? NSTextField {
            cell = reused
            icon = iconView
            preview = previewField
            detail = detailField
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            icon = NSImageView()
            icon.tag = 3
            icon.imageScaling = .scaleProportionallyDown
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 4
            icon.layer?.masksToBounds = true

            preview = NSTextField(labelWithString: "")
            preview.tag = 1
            preview.font = .systemFont(ofSize: 14)
            preview.lineBreakMode = .byTruncatingTail

            detail = NSTextField(labelWithString: "")
            detail.tag = 2
            detail.font = .systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor

            [icon, preview, detail].forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview($0)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 40),
                icon.heightAnchor.constraint(equalToConstant: 40),

                preview.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                preview.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                preview.topAnchor.constraint(equalTo: cell.topAnchor, constant: 9),
                detail.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
                detail.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
                detail.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 5)
            ])
        }

        let item = filteredItems[row]
        if item.isImage {
            let thumbnail = store.images.thumbnail(for: item.id)
            icon.image = thumbnail
                ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            icon.contentTintColor = thumbnail == nil ? .secondaryLabelColor : nil
        } else {
            icon.image = NSImage(
                systemSymbolName: "text.alignleft",
                accessibilityDescription: nil
            )
            icon.contentTintColor = .secondaryLabelColor
        }
        preview.stringValue = item.listPreview
        detail.stringValue = "\(item.timestamp) · \(item.sizeSummary)"
        return cell
    }

    private func updatePreview() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else {
            previewPlaceholder.isHidden = false
            previewImageView.isHidden = true
            previewImageView.image = nil
            previewTextScrollView.isHidden = true
            previewInfoLabel.stringValue = ""
            return
        }

        let item = filteredItems[row]
        previewPlaceholder.isHidden = true
        previewInfoLabel.stringValue =
            "\(item.preciseTimestamp) · \(relativeDate(item.createdAt)) · \(item.sizeSummary)"

        if item.isImage {
            let image = store.images.image(for: item.id)
            previewImageView.image = image
            previewImageView.isHidden = false
            previewTextScrollView.isHidden = true
            if image == nil {
                previewInfoLabel.stringValue = "图片文件已丢失，无法预览"
            }
        } else {
            previewTextView.string = item.text
            previewTextView.scroll(.zero)
            previewTextScrollView.isHidden = false
            previewImageView.isHidden = true
            previewImageView.image = nil
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func relativeDate(_ date: Date) -> String {
        // 刚复制完的记录会被算成“0秒后”，一分钟以内直接说“刚刚”。
        let now = Date()
        guard now.timeIntervalSince(date) >= 60 else { return "刚刚" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    @objc private func activateSelectedItem() {
        pasteSelectedItem()
    }

    private func pasteSelectedItem() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        guard writeToPasteboard(filteredItems[row]) else { return }

        // 回车后总是关闭窗口，并回到刚才使用的应用。
        hide()

        // 自动粘贴需要辅助功能权限。只在首次需要时提示一次，避免每次回车都弹窗。
        guard accessibilityAutomationAllowed() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            Self.pasteWhenCursorAvailable(attemptsLeft: 10)
        }
    }

    /// 光标停在可输入的文本里才自动粘贴，否则内容留在系统剪贴板，
    /// 等用户自己按 ⌘V。目标应用刚被激活时焦点可能还没就绪，所以多试几次。
    private static func pasteWhenCursorAvailable(attemptsLeft: Int) {
        let status = focusedElementTextStatus()
        switch status {
        case .textInput:
            postPasteShortcut()
        case .nonText, .unavailable:
            // 一些浏览器网页输入框不会暴露 AXTextField，但正常的 ⌘V 仍然可用。
            // 等目标应用回到前台后，在最后一次尝试中发送一次快捷键作为兜底。
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

    /// 判断当前聚焦控件是否明确是文本输入；部分应用不会完整暴露 AX 信息。
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
        // ClipTiny runs in the user's GUI session, so use the combined session
        // state rather than the HID-system state used by drivers and daemons.
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
        guard !UserDefaults.standard.bool(forKey: Self.accessibilityPromptedKey) else {
            return false
        }

        UserDefaults.standard.set(true, forKey: Self.accessibilityPromptedKey)
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
