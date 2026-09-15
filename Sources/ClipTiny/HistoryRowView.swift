import AppKit

enum ContentKind: Equatable {
    case image
    case color(hex: String, color: NSColor)
    case link(url: URL)
    case code(lineCount: Int)
    case text
}

extension NSColor {
    static func fromHex(_ hexString: String) -> NSColor? {
        let text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("#") else { return nil }
        let hex = String(text.dropFirst())
        guard hex.count == 3 || hex.count == 4 || hex.count == 6 || hex.count == 8 else { return nil }
        var rgbValue: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&rgbValue) else { return nil }

        switch hex.count {
        case 3:
            let r = CGFloat((rgbValue & 0xF00) >> 8) / 15.0
            let g = CGFloat((rgbValue & 0x0F0) >> 4) / 15.0
            let b = CGFloat(rgbValue & 0x00F) / 15.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        case 4:
            let r = CGFloat((rgbValue & 0xF000) >> 12) / 15.0
            let g = CGFloat((rgbValue & 0x0F00) >> 8) / 15.0
            let b = CGFloat((rgbValue & 0x00F0) >> 4) / 15.0
            let a = CGFloat(rgbValue & 0x000F) / 15.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        case 6:
            let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = CGFloat(rgbValue & 0x0000FF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        case 8:
            let r = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            let g = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            let b = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            let a = CGFloat(rgbValue & 0x000000FF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
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

func detectContentKind(text: String, isImage: Bool) -> ContentKind {
    if isImage { return .image }
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
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isHovered && !isSelected {
            let path = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 4, dy: 3), xRadius: 8, yRadius: 8
            )
            NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
            path.fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 4, dy: 3), xRadius: 8, yRadius: 8
        )
        NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.15 : 0.10).setFill()
        path.fill()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 4, y: bounds.midY - 9, width: 3, height: 18),
            xRadius: 1.5, yRadius: 1.5
        ).fill()
    }
}

final class HistoryCellView: NSTableCellView {
    private let iconBox = NSBox()
    private let icon = NSImageView()
    private let summary = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.titlePosition = .noTitle
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 7
        iconBox.contentViewMargins = .zero

        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 6
        icon.layer?.masksToBounds = true

        summary.font = .systemFont(ofSize: 13, weight: .medium)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        time.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        time.textColor = .secondaryLabelColor
        time.alignment = .right
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)

        [summary, detail].forEach {
            $0.lineBreakMode = .byTruncatingTail
            $0.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        }

        [iconBox, icon, summary, detail, time].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 32),
            iconBox.heightAnchor.constraint(equalToConstant: 32),
            icon.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor),
            icon.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor),
            icon.topAnchor.constraint(equalTo: iconBox.topAnchor),
            icon.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor),

            summary.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 12),
            summary.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -10),
            summary.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            time.centerYAnchor.constraint(equalTo: summary.centerYAnchor),

            detail.leadingAnchor.constraint(equalTo: summary.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: time.trailingAnchor),
            detail.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: HistoryItem, thumbnail: NSImage?) {
        let kind = detectContentKind(text: item.text, isImage: item.isImage)
        let lines = item.text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

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
            summary.stringValue = lines.first ?? item.listPreview
            detail.stringValue = "代码 · \(lineCount) 行 · \(item.sizeSummary)"

        case .text:
            let tint: NSColor = .secondaryLabelColor
            iconBox.fillColor = tint.withAlphaComponent(0.08)
            iconBox.borderWidth = 0
            icon.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "文本")
            icon.imageScaling = .scaleNone
            icon.contentTintColor = tint
            summary.stringValue = lines.first ?? item.listPreview
            detail.stringValue = lines.dropFirst().first ?? "文本 · \(item.sizeSummary)"
        }

        if Date().timeIntervalSince(item.createdAt) < 60 {
            time.stringValue = "刚刚"
        } else {
            let formatter = Calendar.current.isDateInToday(item.createdAt)
                ? Self.timeFormatter : Self.dateFormatter
            time.stringValue = formatter.string(from: item.createdAt)
        }
        toolTip = "\(item.preciseTimestamp) · \(item.sizeSummary)"
    }
}
