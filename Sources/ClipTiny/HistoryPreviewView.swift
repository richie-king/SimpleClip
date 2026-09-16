import AppKit

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

final class FilePreviewCardView: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = .init(pointSize: 48, weight: .regular)

        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.alignment = .center

        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.alignment = .center
        pathLabel.isSelectable = true

        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.alignment = .center

        let stack = NSStackView(views: [iconView, nameLabel, pathLabel, sizeLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(url: URL, sizeSummary: String, isDirectory: Bool) {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        iconView.image = icon
        nameLabel.stringValue = url.lastPathComponent
        pathLabel.stringValue = url.path
        sizeLabel.stringValue = isDirectory ? "文件夹" : sizeSummary
    }
}

final class HistoryPreviewCardView: NSView {
    // Header 区域
    let previewTypeIcon = NSImageView()
    let previewTitle = NSTextField(labelWithString: "内容预览")
    let previewSubtitle = NSTextField(labelWithString: "选择一条记录，查看完整内容")
    let openLinkButton = NSButton(title: "打开链接", target: nil, action: nil)
    let revealFileButton = NSButton(title: "在访达中显示", target: nil, action: nil)
    let maskToggleButton = NSButton(title: "显示明文", target: nil, action: nil)

    // 容器卡片与内部视图
    private let previewBox = NSBox()
    private let previewImageView = NSImageView()
    private let previewTextView = NSTextView()
    private let previewTextScrollView = NSScrollView()
    private let previewColorCard = ColorPreviewCardView()
    private let previewFileCard = FilePreviewCardView()
    private let previewPlaceholder = NSStackView()

    // 底部信息栏
    let previewInfoLabel = NSTextField(labelWithString: "")
    let previewDetailLabel = NSTextField(labelWithString: "")

    var onOpenLink: (() -> Void)?
    var onRevealInFinder: (() -> Void)?

    private var currentItem: HistoryItem?
    private var isMaskingDisabled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // 1. Header 元素
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
        openLinkButton.action = #selector(openLinkAction)
        openLinkButton.toolTip = "在默认浏览器中打开 (⌘O)"
        openLinkButton.isHidden = true

        revealFileButton.bezelStyle = .inline
        revealFileButton.controlSize = .small
        revealFileButton.font = .systemFont(ofSize: 10, weight: .medium)
        revealFileButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        revealFileButton.imagePosition = .imageTrailing
        revealFileButton.target = self
        revealFileButton.action = #selector(revealFileAction)
        revealFileButton.toolTip = "在访达中定位高亮 (⌘R)"
        revealFileButton.isHidden = true

        maskToggleButton.bezelStyle = .inline
        maskToggleButton.controlSize = .small
        maskToggleButton.font = .systemFont(ofSize: 10, weight: .medium)
        maskToggleButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        maskToggleButton.imagePosition = .imageLeading
        maskToggleButton.target = self
        maskToggleButton.action = #selector(toggleMaskAction)
        maskToggleButton.toolTip = "切换敏感凭证显示/遮蔽"
        maskToggleButton.isHidden = true

        let headerStack = NSStackView(views: [previewTypeIcon, previewTitle, previewSubtitle])
        headerStack.orientation = .horizontal
        headerStack.spacing = 6
        headerStack.alignment = .centerY

        let actionsStack = NSStackView(views: [maskToggleButton, revealFileButton, openLinkButton])
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 8
        actionsStack.alignment = .centerY

        // 2. 预览主体 Box
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

        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.drawsBackground = false
        previewTextView.textColor = .textColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        previewTextView.defaultParagraphStyle = paragraph
        previewTextView.textContainerInset = NSSize(width: 6, height: 6)
        previewTextView.isVerticallyResizable = true
        previewTextView.isHorizontallyResizable = false
        previewTextView.autoresizingMask = [.width]
        previewTextView.textContainer?.widthTracksTextView = true

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
        emptyIcon.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        emptyIcon.symbolConfiguration = .init(pointSize: 30, weight: .light)
        emptyIcon.contentTintColor = .tertiaryLabelColor

        let emptyTitle = NSTextField(labelWithString: "预览")
        emptyTitle.font = .systemFont(ofSize: 14, weight: .medium)
        emptyTitle.textColor = .secondaryLabelColor

        let emptyDetail = NSTextField(labelWithString: "选择记录查看完整内容")
        emptyDetail.font = .systemFont(ofSize: 12)
        emptyDetail.textColor = .secondaryLabelColor

        previewPlaceholder.orientation = .vertical
        previewPlaceholder.alignment = .centerX
        previewPlaceholder.spacing = 8
        [emptyIcon, emptyTitle, emptyDetail].forEach { previewPlaceholder.addArrangedSubview($0) }

        let metadataDivider = NSBox()
        metadataDivider.boxType = .separator

        guard let container = previewBox.contentView else { return }
        [previewImageView, previewTextScrollView, previewColorCard, previewFileCard, previewPlaceholder,
         metadataDivider, previewInfoLabel, previewDetailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }

        [headerStack, actionsStack, previewBox].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            headerStack.heightAnchor.constraint(equalToConstant: 24),

            actionsStack.centerYAnchor.constraint(equalTo: headerStack.centerYAnchor),
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            previewBox.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 10),
            previewBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewBox.bottomAnchor.constraint(equalTo: bottomAnchor),

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
            previewColorCard.heightAnchor.constraint(equalToConstant: 160),

            previewFileCard.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            previewFileCard.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -10),
            previewFileCard.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -24),

            previewImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            previewImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            previewImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            previewImageView.bottomAnchor.constraint(equalTo: metadataDivider.topAnchor, constant: -8),

            previewTextScrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            previewTextScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            previewTextScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            previewTextScrollView.bottomAnchor.constraint(equalTo: metadataDivider.topAnchor, constant: -8)
        ])
    }

    @objc private func openLinkAction() {
        onOpenLink?()
    }

    @objc private func revealFileAction() {
        onRevealInFinder?()
    }

    @objc private func toggleMaskAction() {
        isMaskingDisabled.toggle()
        updateMaskButtonState()
        updateTextContent()
    }

    private func updateMaskButtonState() {
        if isMaskingDisabled {
            maskToggleButton.title = "遮蔽凭证"
            maskToggleButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        } else {
            maskToggleButton.title = "显示明文"
            maskToggleButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        }
    }

    func showEmptyState() {
        currentItem = nil
        isMaskingDisabled = false
        previewPlaceholder.isHidden = false
        previewImageView.isHidden = true
        previewImageView.image = nil
        previewTextScrollView.isHidden = true
        previewColorCard.isHidden = true
        previewFileCard.isHidden = true
        openLinkButton.isHidden = true
        revealFileButton.isHidden = true
        maskToggleButton.isHidden = true

        previewTypeIcon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        previewTitle.stringValue = "内容预览"
        previewSubtitle.stringValue = "选择一条记录，查看完整内容"
        previewInfoLabel.stringValue = "选择记录后按回车粘贴"
        previewDetailLabel.stringValue = ""
    }

    func display(item: HistoryItem, images: ImageVault) {
        if currentItem?.id != item.id {
            isMaskingDisabled = false
        }
        currentItem = item
        updateMaskButtonState()

        previewPlaceholder.isHidden = true
        previewInfoLabel.stringValue = item.preciseTimestamp
        previewInfoLabel.toolTip = "复制时间：\(item.preciseTimestamp)"

        let kind = detectContentKind(item: item)
        switch kind {
        case .image:
            hideAllContentCards()
            previewImageView.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemPurple
            previewTitle.stringValue = "图片"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(item.sizeSummary)"
            previewDetailLabel.stringValue = "PNG 图像"

            let image = images.image(for: item.id)
            previewImageView.image = image
            if image == nil {
                previewInfoLabel.stringValue = "图片文件已丢失，无法预览"
            }

        case .file(let url, let isDirectory):
            hideAllContentCards()
            previewFileCard.isHidden = false
            revealFileButton.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: isDirectory ? "folder" : "doc", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemBlue
            previewTitle.stringValue = isDirectory ? "文件夹" : "文件"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(url.lastPathComponent)"
            previewDetailLabel.stringValue = item.sizeSummary
            previewFileCard.configure(url: url, sizeSummary: item.sizeSummary, isDirectory: isDirectory)

        case .color(let hex, let color):
            hideAllContentCards()
            previewColorCard.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemPink
            previewTitle.stringValue = "颜色"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(color.hexRGBString)"
            previewDetailLabel.stringValue = color.rgbComponentsString
            previewColorCard.configure(hex: hex, color: color)

        case .link(let url):
            hideAllContentCards()
            previewTextScrollView.isHidden = false
            openLinkButton.isHidden = false

            previewTypeIcon.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemTeal
            previewTitle.stringValue = "链接"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(url.host ?? "")"
            previewDetailLabel.stringValue = "\(item.text.count) 字符"

            previewTextView.font = .systemFont(ofSize: 13)
            updateTextContent()

        case .code(let lineCount):
            hideAllContentCards()
            previewTextScrollView.isHidden = false

            let isSensitive = SensitiveMasker.isSensitive(item.text)
            maskToggleButton.isHidden = !isSensitive

            previewTypeIcon.image = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .systemOrange
            previewTitle.stringValue = isSensitive ? "代码 (含敏感凭证)" : "代码"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(lineCount) 行"
            previewDetailLabel.stringValue = "\(item.text.count) 字符"

            previewTextView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            updateTextContent()

        case .text:
            hideAllContentCards()
            previewTextScrollView.isHidden = false

            let isSensitive = SensitiveMasker.isSensitive(item.text)
            maskToggleButton.isHidden = !isSensitive

            previewTypeIcon.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
            previewTypeIcon.contentTintColor = .secondaryLabelColor
            previewTitle.stringValue = isSensitive ? "敏感凭证文本" : "文本"
            previewSubtitle.stringValue = "\(relativeDate(item.createdAt))复制 · \(item.sizeSummary)"
            previewDetailLabel.stringValue = "\(item.text.count) 字符"

            previewTextView.font = .systemFont(ofSize: 13)
            updateTextContent()
        }
    }

    private func hideAllContentCards() {
        openLinkButton.isHidden = true
        revealFileButton.isHidden = true
        maskToggleButton.isHidden = true
        previewImageView.isHidden = true
        previewImageView.image = nil
        previewTextScrollView.isHidden = true
        previewColorCard.isHidden = true
        previewFileCard.isHidden = true
    }

    private func updateTextContent() {
        guard let item = currentItem else { return }
        let isSensitive = SensitiveMasker.isSensitive(item.text)
        let displayText: String
        if isSensitive && !isMaskingDisabled {
            displayText = SensitiveMasker.mask(item.text)
        } else {
            displayText = item.text
        }
        previewTextView.string = displayText
        previewTextView.scroll(.zero)
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
}
