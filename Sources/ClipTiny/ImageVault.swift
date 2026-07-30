import AppKit
import CryptoKit

/// 图片不写进历史 JSON，而是按记录 id 单独加密存盘。
/// 每条图片记录有两个文件：原图 `<id>.img` 和缩略图 `<id>.thumb`。
final class ImageVault {
    private static let fullSuffix = "img"
    private static let thumbnailSuffix = "thumb"

    private let directory: URL
    private let key: SymmetricKey?
    private let thumbnailCache = NSCache<NSString, NSImage>()

    init(directory: URL, key: SymmetricKey?) {
        self.directory = directory
        self.key = key
        thumbnailCache.countLimit = 60

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    func store(id: UUID, capture: ImageCapture) -> Bool {
        guard
            write(capture.pngData, to: url(for: id, suffix: Self.fullSuffix)),
            write(capture.thumbnailData, to: url(for: id, suffix: Self.thumbnailSuffix))
        else {
            remove(id: id)
            return false
        }
        return true
    }

    func pngData(for id: UUID) -> Data? {
        read(url(for: id, suffix: Self.fullSuffix))
    }

    func image(for id: UUID) -> NSImage? {
        pngData(for: id).flatMap(NSImage.init(data:))
    }

    func thumbnail(for id: UUID) -> NSImage? {
        let cacheKey = id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) { return cached }
        guard
            let data = read(url(for: id, suffix: Self.thumbnailSuffix)),
            let image = NSImage(data: data)
        else { return nil }
        thumbnailCache.setObject(image, forKey: cacheKey)
        return image
    }

    func remove(id: UUID) {
        thumbnailCache.removeObject(forKey: id.uuidString as NSString)
        try? FileManager.default.removeItem(at: url(for: id, suffix: Self.fullSuffix))
        try? FileManager.default.removeItem(at: url(for: id, suffix: Self.thumbnailSuffix))
    }

    /// 删除历史里已经没有对应记录的图片文件。
    func removeOrphans(keeping ids: Set<UUID>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            let base = (name as NSString).deletingPathExtension
            guard let id = UUID(uuidString: base), !ids.contains(id) else { continue }
            remove(id: id)
        }
    }

    private func url(for id: UUID, suffix: String) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(suffix)")
    }

    private func write(_ data: Data, to url: URL) -> Bool {
        guard
            let key,
            let sealedBox = try? AES.GCM.seal(data, using: key),
            let encrypted = sealedBox.combined
        else { return false }

        do {
            try encrypted.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            NSLog("ClipTiny 无法保存图片：%@", error.localizedDescription)
            return false
        }
    }

    private func read(_ url: URL) -> Data? {
        guard
            let key,
            let encrypted = try? Data(contentsOf: url),
            let sealedBox = try? AES.GCM.SealedBox(combined: encrypted),
            let plaintext = try? AES.GCM.open(sealedBox, using: key)
        else { return nil }
        return plaintext
    }
}
