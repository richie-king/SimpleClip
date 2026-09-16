import AppKit
import CryptoKit

enum HistoryKind: String, Codable {
    case text
    case image
    case file
}

struct HistoryItem: Codable, Equatable {
    let id: UUID
    let kind: HistoryKind
    /// 文本记录的正文；图片记录保存一句可搜索的描述；文件记录保存文件名。
    let text: String
    let createdAt: Date
    let imageDigest: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let byteCount: Int?
    var isPinned: Bool
    let filePath: String?

    var fileURL: URL? {
        filePath.map { URL(fileURLWithPath: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, text, createdAt, imageDigest, pixelWidth, pixelHeight, byteCount
        case isPinned, filePath
    }

    init(
        id: UUID,
        kind: HistoryKind,
        text: String,
        createdAt: Date,
        imageDigest: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        byteCount: Int? = nil,
        isPinned: Bool = false,
        filePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.imageDigest = imageDigest
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.isPinned = isPinned
        self.filePath = filePath
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
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(imageDigest, forKey: .imageDigest)
        try container.encodeIfPresent(pixelWidth, forKey: .pixelWidth)
        try container.encodeIfPresent(pixelHeight, forKey: .pixelHeight)
        try container.encodeIfPresent(byteCount, forKey: .byteCount)
        if isPinned {
            try container.encode(isPinned, forKey: .isPinned)
        }
        try container.encodeIfPresent(filePath, forKey: .filePath)
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
    var isFile: Bool { kind == .file }

    /// 列表里显示到分钟，预览区显示到秒。
    var timestamp: String { listTimestampFormatter.string(from: createdAt) }

    var preciseTimestamp: String { preciseTimestampFormatter.string(from: createdAt) }

    /// 列表里的单行摘要，换行和制表符换成可见符号。
    var listPreview: String {
        if isImage { return text }
        if isFile { return text }
        return text
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\t", with: " ⇥ ")
    }

    var sizeSummary: String {
        if isImage {
            let pixels = "\(pixelWidth ?? 0) × \(pixelHeight ?? 0)"
            let bytes = ByteCountFormatter.string(
                fromByteCount: Int64(byteCount ?? 0),
                countStyle: .file
            )
            return "\(pixels) · \(bytes)"
        }
        if isFile {
            guard let bytes = byteCount else { return "文件" }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        return "\(text.count) 个字符"
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

    private let defaults: UserDefaults
    private let debounceInterval: TimeInterval
    private var saveTimer: Timer?
    private var hasPendingSave = false

    convenience init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ClipTiny", isDirectory: true)
        var key: SymmetricKey?
        do {
            key = try KeychainKeyStore.loadOrCreateKey()
        } catch {
            key = nil
            NSLog("ClipTiny 无法访问加密密钥：%@", error.localizedDescription)
        }
        self.init(directory: support, key: key, defaults: .standard, debounceInterval: 0.5)
    }

    /// 显式提供存储依赖，让测试不访问用户历史、偏好设置和钥匙串。默认 debounceInterval 为 0 确保同步落盘。
    init(
        directory: URL,
        key: SymmetricKey?,
        defaults: UserDefaults,
        debounceInterval: TimeInterval = 0.0
    ) {
        self.defaults = defaults
        self.debounceInterval = debounceInterval
        let savedMaximumCount = defaults.integer(forKey: Self.maximumCountDefaultsKey)
        maximumCount = Self.availableMaximumCounts.contains(savedMaximumCount)
            ? savedMaximumCount
            : Self.defaultMaximumCount
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        fileURL = directory.appendingPathComponent("history.enc")
        encryptionKey = key
        images = ImageVault(
            directory: directory.appendingPathComponent("images", isDirectory: true),
            key: key
        )
        load()
    }

    deinit {
        flushSync()
    }

    func setMaximumCount(_ count: Int) {
        guard Self.availableMaximumCounts.contains(count) else { return }
        guard count != maximumCount else { return }

        maximumCount = count
        defaults.set(count, forKey: Self.maximumCountDefaultsKey)
        trim()
        save(immediate: true)
        onChange?()
    }

    func add(_ text: String) {
        guard !text.isEmpty else { return }

        var wasPinned = false
        if let existing = items.first(where: { $0.kind == .text && $0.text == text }) {
            wasPinned = existing.isPinned
            items.removeAll { $0.kind == .text && $0.text == text }
        }

        let newItem = HistoryItem(
            id: UUID(),
            kind: .text,
            text: text,
            createdAt: Date(),
            isPinned: wasPinned
        )
        items.insert(newItem, at: 0)
        sortItems()
        trim()
        save()
        onChange?()
    }

    func add(_ capture: ImageCapture) {
        guard capture.pngData.count <= maximumImageBytes else { return }

        // 同一张图重新复制时只把旧记录移到最前，保留置顶状态，不再复制一份文件。
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
                    byteCount: existing.byteCount,
                    isPinned: existing.isPinned,
                    filePath: existing.filePath
                ),
                at: 0
            )
            sortItems()
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
                byteCount: capture.pngData.count,
                isPinned: false
            ),
            at: 0
        )
        sortItems()
        trim()
        save()
        onChange?()
    }

    func addFile(url: URL) {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return }

        var wasPinned = false
        if let existing = items.first(where: { $0.kind == .file && $0.filePath == path }) {
            wasPinned = existing.isPinned
            items.removeAll { $0.kind == .file && $0.filePath == path }
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let byteCount = (attributes?[.size] as? NSNumber)?.intValue

        let displayName = url.lastPathComponent.isEmpty ? path : url.lastPathComponent
        let newItem = HistoryItem(
            id: UUID(),
            kind: .file,
            text: displayName,
            createdAt: Date(),
            byteCount: byteCount,
            isPinned: wasPinned,
            filePath: path
        )
        items.insert(newItem, at: 0)
        sortItems()
        trim()
        save()
        onChange?()
    }

    func delete(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        if removed.isImage {
            images.remove(id: removed.id)
        }
        save()
        onChange?()
    }

    func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let current = items[index]
        let updated = HistoryItem(
            id: current.id,
            kind: current.kind,
            text: current.text,
            createdAt: current.createdAt,
            imageDigest: current.imageDigest,
            pixelWidth: current.pixelWidth,
            pixelHeight: current.pixelHeight,
            byteCount: current.byteCount,
            isPinned: !current.isPinned,
            filePath: current.filePath
        )
        items[index] = updated
        sortItems()
        save()
        onChange?()
    }

    func clear() {
        items.filter(\.isImage).forEach { images.remove(id: $0.id) }
        items.removeAll()
        save(immediate: true)
        onChange?()
    }

    private func sortItems() {
        items.sort { item1, item2 in
            if item1.isPinned != item2.isPinned {
                return item1.isPinned && !item2.isPinned
            }
            return item1.createdAt > item2.createdAt
        }
    }

    private func trim() {
        guard items.count > maximumCount else { return }

        // 置顶记录绝不被容量截断，只裁剪最旧的非置顶记录
        var unpinnedIndices: [Int] = []
        for (index, item) in items.enumerated() {
            if !item.isPinned {
                unpinnedIndices.append(index)
            }
        }
        let excessCount = items.count - maximumCount
        guard excessCount > 0, !unpinnedIndices.isEmpty else { return }

        let toRemoveIndices = Array(unpinnedIndices.suffix(excessCount))
        let toRemoveSet = Set(toRemoveIndices)

        var newItems: [HistoryItem] = []
        var dropped: [HistoryItem] = []

        for (index, item) in items.enumerated() {
            if toRemoveSet.contains(index) {
                dropped.append(item)
            } else {
                newItems.append(item)
            }
        }

        items = newItems
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
        sortItems()
        images.removeOrphans(keeping: Set(items.map(\.id)))
    }

    func save(immediate: Bool = false) {
        hasPendingSave = true
        if immediate || debounceInterval <= 0 {
            saveTimer?.invalidate()
            saveTimer = nil
            performDiskSaveSync()
        } else {
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                self?.performDiskSaveAsync()
            }
        }
    }

    func flushSync() {
        saveTimer?.invalidate()
        saveTimer = nil
        if hasPendingSave {
            performDiskSaveSync()
        }
    }

    private func performDiskSaveSync() {
        hasPendingSave = false
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

    private func performDiskSaveAsync() {
        hasPendingSave = false
        guard let encryptionKey else { return }
        let snapshot = items
        let targetURL = fileURL

        DispatchQueue.global(qos: .utility).async {
            guard
                let plaintext = try? JSONEncoder().encode(snapshot),
                let sealedBox = try? AES.GCM.seal(
                    plaintext,
                    using: encryptionKey
                ),
                let encrypted = sealedBox.combined
            else { return }

            do {
                try encrypted.write(to: targetURL, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: targetURL.path
                )
            } catch {
                NSLog("ClipTiny 无法保存加密历史：%@", error.localizedDescription)
            }
        }
    }
}
