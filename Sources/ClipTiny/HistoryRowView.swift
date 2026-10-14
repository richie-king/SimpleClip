import AppKit

enum ContentKind: Equatable {
    case image
    case file(url: URL, isDirectory: Bool)
    case color(hex: String, color: NSColor)
    case link(url: URL)
    case code(lineCount: Int)
    case text
}

extension NSColor {
    static func fromHex(_ hexString: String) -> NSColor? {
        let text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("#") else { return nil }
        var hex = String(text.dropFirst())
        if hex.count == 3 || hex.count == 4 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        if hex.count == 6 { hex += "FF" }
        guard hex.count == 8 else { return nil }
        var rgbValue: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&rgbValue) else { return nil }

        let r = CGFloat((rgbValue >> 24) & 0xFF) / 255.0
        let g = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
        let b = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
        let a = CGFloat(rgbValue & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexRGBString: String {
        guard let converted = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(converted.redComponent * 255))
        let g = Int(round(converted.greenComponent * 255))
        let b = Int(round(converted.blueComponent * 255))
        if converted.alphaComponent < 1.0 {
            let a = Int(round(converted.alphaComponent * 255))
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbComponentsString: String {
        guard let converted = usingColorSpace(.sRGB) else { return "rgb(0, 0, 0)" }
        let r = Int(round(converted.redComponent * 255))
        let g = Int(round(converted.greenComponent * 255))
        let b = Int(round(converted.blueComponent * 255))
        if converted.alphaComponent < 1.0 {
            return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, converted.alphaComponent)
        }
        return String(format: "rgb(%d, %d, %d)", r, g, b)
    }
}

func detectContentKind(item: HistoryItem) -> ContentKind {
    if item.isImage { return .image }
    if item.isFile, let url = item.fileURL {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return .file(url: url, isDirectory: isDir)
    }
    return detectContentKind(text: item.text)
}

func detectContentKind(text: String) -> ContentKind {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let color = NSColor.fromHex(trimmed) {
        return .color(hex: trimmed, color: color)
    }
    if let url = URL(string: trimmed),
       ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
       url.host != nil,
       !trimmed.contains(where: { $0.isWhitespace }) {
        return .link(url: url)
    }
    let lines = text.split(whereSeparator: { $0.isNewline })
    if isCodeContent(text: trimmed, lineCount: lines.count) {
        return .code(lineCount: lines.count)
    }
    return .text
}

private func isCodeContent(text: String, lineCount: Int) -> Bool {
    if text.hasPrefix("{") && text.hasSuffix("}") { return true }
    if text.hasPrefix("[") && text.hasSuffix("]") && lineCount > 1 { return true }
    if text.hasPrefix("<!DOCTYPE html") || text.hasPrefix("<html") { return true }
    let keywords = [
        "func ", "def ", "class ", "struct ", "enum ", "import ", "const ",
        "let ", "var ", "return ", "if (", "for (", "while (", "function(",
        "SELECT ", "FROM ", "WHERE ", "curl ", "git ", "npm ", "docker ",
        "swift ", "cd ", "mkdir ", "#!/bin/", "console.log"
    ]
    for kw in keywords {
        if text.contains(kw) {
            if lineCount > 1 || text.contains(";") || text.contains("{") || kw.hasPrefix("curl") || kw.hasPrefix("git") || kw.hasPrefix("#!/") {
                return true
            }
        }
    }
    return false
}

final class HistoryRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isHovered = false
        }
    }

    func updateHoverState() {
        guard let window = self.window else {
            if isHovered { isHovered = false }
            return
        }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = convert(mouseInWindow, from: nil)
        let isInside = visibleRect.contains(mouseInView) && bounds.contains(mouseInView)
        if isHovered != isInside {
            isHovered = isInside
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeInActiveApp,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area

        updateHoverState()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private var pillPath: NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 2), xRadius: 8, yRadius: 8)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isHovered && !isSelected {
            NSColor.textColor.withAlphaComponent(0.045).setFill()
            pillPath.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.16 : 0.12).setFill()
        pillPath.fill()

        let indicator = NSBezierPath(
            roundedRect: NSRect(x: 5, y: bounds.midY - 11, width: 3.5, height: 22),
            xRadius: 1.75, yRadius: 1.75
        )
        NSColor.controlAccentColor.setFill()
        indicator.fill()
    }
}

final class HistoryCellView: NSTableCellView {
    private let iconBox = NSBox()
    private let icon = NSImageView()
    private let summary = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let pinIcon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.titlePosition = .noTitle
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 8
        iconBox.contentViewMargins = .zero

        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 6.5
        icon.layer?.masksToBounds = true

        summary.font = .systemFont(ofSize: 13, weight: .medium)
        detail.font = .systemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor

        pinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "置顶")
        pinIcon.symbolConfiguration = .init(pointSize: 9.5, weight: .semibold)
        pinIcon.contentTintColor = .systemOrange
        pinIcon.isHidden = true

        time.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        time.textColor = .tertiaryLabelColor
        time.alignment = .right
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        [summary, detail].forEach {
            $0.lineBreakMode = .byTruncatingTail
            $0.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        }

        [iconBox, icon, summary, detail, pinIcon, time].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 34),
            iconBox.heightAnchor.constraint(equalToConstant: 34),
            icon.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor),
            icon.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor),
            icon.topAnchor.constraint(equalTo: iconBox.topAnchor),
            icon.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor),

            summary.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 11),
            summary.trailingAnchor.constraint(equalTo: pinIcon.leadingAnchor, constant: -6),
            summary.topAnchor.constraint(equalTo: topAnchor, constant: 10.5),

            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            time.centerYAnchor.constraint(equalTo: summary.centerYAnchor),

            pinIcon.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -5),
            pinIcon.centerYAnchor.constraint(equalTo: time.centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 11),
            pinIcon.heightAnchor.constraint(equalToConstant: 11),

            detail.leadingAnchor.constraint(equalTo: summary.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: time.trailingAnchor),
            detail.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: HistoryItem, thumbnail: NSImage?) {
        let kind = detectContentKind(item: item)
        let lines = item.text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        pinIcon.isHidden = !item.isPinned

        switch kind {
        case .image:
            if let thumbnail {
                iconBox.fillColor = .clear
                iconBox.borderWidth = 0.5
                iconBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.4)
                icon.image = thumbnail
                icon.imageScaling = .scaleProportionallyUpOrDown
                icon.contentTintColor = nil
            } else {
                let tint: NSColor = .systemPurple
                iconBox.fillColor = tint.withAlphaComponent(0.12)
                iconBox.borderWidth = 0
                icon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "图片")
                icon.imageScaling = .scaleNone
                icon.contentTintColor = tint
            }
            summary.stringValue = lines.first ?? item.listPreview
            detail.stringValue = "图片 · \(item.sizeSummary)"

        case .file(let url, let isDirectory):
            iconBox.fillColor = .clear
            iconBox.borderWidth = 0
            let fileIcon = NSWorkspace.shared.icon(forFile: url.path)
            fileIcon.size = NSSize(width: 32, height: 32)
            icon.image = fileIcon
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.contentTintColor = nil
            summary.stringValue = item.text
            detail.stringValue = isDirectory ? "文件夹" : "文件 · \(item.sizeSummary)"

        case .color(let hex, let color):
            iconBox.fillColor = color
            iconBox.borderWidth = 0.5
            iconBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.5)
            icon.image = nil
            summary.stringValue = hex
            detail.stringValue = "颜色 · \(color.hexRGBString)"

        case .link(let url):
            let tint: NSColor = .systemTeal
            iconBox.fillColor = tint.withAlphaComponent(0.12)
            iconBox.borderWidth = 0
            icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: "链接")
            icon.imageScaling = .scaleNone
            icon.contentTintColor = tint
            summary.stringValue = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            detail.stringValue = "链接 · \(url.host ?? "")"

        case .code(let lineCount):
            let tint: NSColor = .systemOrange
            iconBox.fillColor = tint.withAlphaComponent(0.12)
            iconBox.borderWidth = 0
            icon.image = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: "代码")
            icon.imageScaling = .scaleNone
            icon.contentTintColor = tint

            let isSensitive = SensitiveMasker.isSensitive(item.text)
            let rawFirstLine = lines.first ?? item.listPreview
            summary.stringValue = isSensitive ? SensitiveMasker.mask(rawFirstLine) : rawFirstLine
            detail.stringValue = isSensitive
                ? "代码 (含敏感凭证) · \(item.sizeSummary)"
                : "代码 · \(lineCount) 行 · \(item.sizeSummary)"

        case .text:
            let tint: NSColor = .secondaryLabelColor
            iconBox.fillColor = tint.withAlphaComponent(0.08)
            iconBox.borderWidth = 0
            icon.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "文本")
            icon.imageScaling = .scaleNone
            icon.contentTintColor = tint

            let isSensitive = SensitiveMasker.isSensitive(item.text)
            let rawFirstLine = lines.first ?? item.listPreview
            summary.stringValue = isSensitive ? SensitiveMasker.mask(rawFirstLine) : rawFirstLine
            if isSensitive {
                detail.stringValue = "敏感凭证 (已脱敏) · \(item.sizeSummary)"
            } else {
                detail.stringValue = lines.dropFirst().first ?? "文本 · \(item.sizeSummary)"
            }
        }

        if Date().timeIntervalSince(item.createdAt) < 60 {
            time.stringValue = "刚刚"
        } else if Calendar.current.isDateInToday(item.createdAt) {
            time.stringValue = item.createdAt.formatted(Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        } else {
            time.stringValue = item.createdAt.formatted(Date.FormatStyle().month(.twoDigits).day(.twoDigits))
        }
        toolTip = "\(item.preciseTimestamp) · \(item.sizeSummary)"
    }
}
