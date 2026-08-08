import AppKit
import CryptoKit

enum HistoryKind: String, Codable {
    case text
    case image
}

struct HistoryItem: Codable, Equatable {
    let id: UUID
    let kind: HistoryKind
    /// 文本记录的正文；图片记录保存一句可搜索的描述。
    let text: String
    let createdAt: Date
    let imageDigest: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let byteCount: Int?

    init(
        id: UUID,
        kind: HistoryKind,
        text: String,
        createdAt: Date,
        imageDigest: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        byteCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.imageDigest = imageDigest
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decodeIfPresent(HistoryKind.self, forKey: .kind) ?? .text
        imageDigest = try container.decodeIfPresent(String.self, forKey: .imageDigest)
        pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
    }
}

/// 固定格式的时间戳，用 POSIX 区域避免跟随系统改成 12 小时制。
private let listTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
}()

private let preciseTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

extension HistoryItem {
    var isImage: Bool { kind == .image }

    /// 列表里显示到分钟，预览区显示到秒。
    var timestamp: String { listTimestampFormatter.string(from: createdAt) }

    var preciseTimestamp: String { preciseTimestampFormatter.string(from: createdAt) }

    /// 列表里的单行摘要，换行和制表符换成可见符号。
    var listPreview: String {
        guard !isImage else { return text }
        return text
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\t", with: " ⇥ ")
    }

    var sizeSummary: String {
        guard isImage else { return "\(text.count) 个字符" }
        let pixels = "\(pixelWidth ?? 0) × \(pixelHeight ?? 0)"
        let bytes = ByteCountFormatter.string(
            fromByteCount: Int64(byteCount ?? 0),
            countStyle: .file
        )
        return "\(pixels) · \(bytes)"
    }
}

final class HistoryStore {
    static let availableMaximumCounts = [50, 100, 200, 500]

    private static let maximumCountDefaultsKey = "MaximumHistoryItemCount"
    private static let defaultMaximumCount = 100

    private(set) var items: [HistoryItem] = []
    var onChange: (() -> Void)?

    let images: ImageVault
    private(set) var maximumCount: Int

    private let maximumImageBytes = 20 * 1024 * 1024
    private let fileURL: URL
    private let encryptionKey: SymmetricKey?

    init() {
        let savedMaximumCount = UserDefaults.standard.integer(
            forKey: Self.maximumCountDefaultsKey
        )
        maximumCount = Self.availableMaximumCounts.contains(savedMaximumCount)
            ? savedMaximumCount
            : Self.defaultMaximumCount

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ClipTiny", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: support.path
        )

        fileURL = support.appendingPathComponent("history.enc")

        var key: SymmetricKey?
        do {
            key = try KeychainKeyStore.loadOrCreateKey()
        } catch {
            key = nil
            NSLog("ClipTiny 无法访问加密密钥：%@", error.localizedDescription)
        }
        encryptionKey = key
        images = ImageVault(
            directory: support.appendingPathComponent("images", isDirectory: true),
            key: key
        )
        load()
    }

    func setMaximumCount(_ count: Int) {
        guard Self.availableMaximumCounts.contains(count) else { return }
        guard count != maximumCount else { return }

        maximumCount = count
        UserDefaults.standard.set(count, forKey: Self.maximumCountDefaultsKey)
        trim()
        save()
        onChange?()
    }

    func add(_ text: String) {
        guard !text.isEmpty else { return }

        items.removeAll { $0.kind == .text && $0.text == text }
        items.insert(
            HistoryItem(id: UUID(), kind: .text, text: text, createdAt: Date()),
            at: 0
        )
        trim()
        save()
        onChange?()
    }

    func add(_ capture: ImageCapture) {
        guard capture.pngData.count <= maximumImageBytes else { return }

        // 同一张图重新复制时只把旧记录移到最前，不再复制一份文件。
        if let index = items.firstIndex(where: { $0.imageDigest == capture.digest }) {
            let existing = items.remove(at: index)
            items.insert(
                HistoryItem(
                    id: existing.id,
                    kind: .image,
                    text: existing.text,
                    createdAt: Date(),
                    imageDigest: existing.imageDigest,
                    pixelWidth: existing.pixelWidth,
                    pixelHeight: existing.pixelHeight,
                    byteCount: existing.byteCount
                ),
                at: 0
            )
            save()
            onChange?()
            return
        }

        let id = UUID()
        guard images.store(id: id, capture: capture) else { return }
        items.insert(
            HistoryItem(
                id: id,
                kind: .image,
                text: "图片 \(capture.pixelWidth) × \(capture.pixelHeight)",
                createdAt: Date(),
                imageDigest: capture.digest,
                pixelWidth: capture.pixelWidth,
                pixelHeight: capture.pixelHeight,
                byteCount: capture.pngData.count
            ),
            at: 0
        )
        trim()
        save()
        onChange?()
    }

    func clear() {
        items.filter(\.isImage).forEach { images.remove(id: $0.id) }
        items.removeAll()
        save()
        onChange?()
    }

    private func trim() {
        guard items.count > maximumCount else { return }
        let dropped = items.suffix(items.count - maximumCount)
        items.removeLast(items.count - maximumCount)
        dropped.filter(\.isImage).forEach { images.remove(id: $0.id) }
    }

    private func load() {
        guard
            let encryptionKey,
            let encrypted = try? Data(contentsOf: fileURL),
            let sealedBox = try? AES.GCM.SealedBox(combined: encrypted),
            let plaintext = try? AES.GCM.open(
                sealedBox,
                using: encryptionKey
            ),
            let decoded = try? JSONDecoder().decode(
                [HistoryItem].self,
                from: plaintext
            )
        else { return }
        items = Array(decoded.prefix(maximumCount))
        images.removeOrphans(keeping: Set(items.map(\.id)))
    }

    private func save() {
        guard
            let encryptionKey,
            let plaintext = try? JSONEncoder().encode(items),
            let sealedBox = try? AES.GCM.seal(
                plaintext,
                using: encryptionKey
            ),
            let encrypted = sealedBox.combined
        else { return }

        do {
            try encrypted.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            NSLog("ClipTiny 无法保存加密历史：%@", error.localizedDescription)
        }
    }
}
