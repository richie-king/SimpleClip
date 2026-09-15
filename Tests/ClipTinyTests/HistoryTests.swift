import AppKit
import CryptoKit
import Testing
@testable import ClipTiny

@Suite(.serialized)
@MainActor
final class HistoryTests {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var key: SymmetricKey!
    private var store: HistoryStore!
    private var pasteboard: NSPasteboard!

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "ClipTinyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        key = SymmetricKey(size: .bits256)
        store = reload()
        pasteboard = NSPasteboard.withUniqueName()
    }

    deinit {
        pasteboard.releaseGlobally()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func reload() -> HistoryStore {
        HistoryStore(directory: directory, key: key, defaults: defaults)
    }

    private func capture() throws -> ImageCapture {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let bytes = try #require(bitmap.bitmapData)
        bytes.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        pasteboard.clearContents()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ClipTinyTests.PNG", code: 1)
        }
        pasteboard.setData(png, forType: .png)
        return try #require(ClipboardImage.read(from: pasteboard))
    }

    @Test
    func testTextDeduplicationAndEmptyInput() {
        var changes = 0
        store.onChange = { changes += 1 }
        store.add("")
        store.add("第一条")
        store.add("second")
        store.add("第一条")
        #expect(store.items.map(\.text) == ["第一条", "second"])
        #expect(changes == 3)
        #expect(reload().items == store.items)
    }

    @Test
    func testMaximumCountPersistsAndRejectsUnsupportedValues() {
        #expect(store.maximumCount == 100)
        for index in 0..<105 { store.add("条目 \(index)") }
        #expect(store.items.count == 100)
        store.setMaximumCount(50)
        #expect(store.items.count == 50)
        #expect(store.items.last?.text == "条目 55")
        store.setMaximumCount(1)
        #expect(store.maximumCount == 50)
        #expect(reload().maximumCount == 50)
        #expect(reload().items == store.items)
    }

    @Test
    func testEncryptedHistoryRoundTripAndPermissions() throws {
        let secret = "不能出现在磁盘上的剪贴板正文"
        store.add(secret)
        let url = directory.appendingPathComponent("history.enc")
        let encrypted = try Data(contentsOf: url)
        #expect(encrypted.range(of: Data(secret.utf8)) == nil)
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key)
        #expect(try JSONDecoder().decode([HistoryItem].self, from: plaintext) == store.items)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(HistoryStore(directory: directory, key: SymmetricKey(size: .bits256), defaults: defaults).items.isEmpty)
        try Data("损坏文件".utf8).write(to: url)
        #expect(reload().items.isEmpty)
    }

    @Test
    func testMissingKeyKeepsTextInMemoryWithoutWriting() throws {
        let unavailable = HistoryStore(directory: directory, key: nil, defaults: defaults)
        unavailable.add("临时文本")
        unavailable.add(try capture())
        #expect(unavailable.items.map(\.text) == ["临时文本"])
        #expect(!(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.enc").path)))
    }

    @Test
    func testImageDeduplicationEncryptionAndClear() throws {
        let image = try capture()
        store.add(image)
        let id = try #require(store.items.first?.id)
        store.add("文本")
        store.add(image)
        #expect(store.items.count == 2)
        #expect(store.items.first?.id == id)
        let images = directory.appendingPathComponent("images")
        #expect(try FileManager.default.contentsOfDirectory(atPath: images.path).count == 2)
        for suffix in ["img", "thumb"] {
            let url = images.appendingPathComponent("\(id.uuidString).\(suffix)")
            #expect(NSImage(data: try Data(contentsOf: url)) == nil)
            #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        #expect(reload().images.pngData(for: id) == image.pngData)
        #expect(store.images.thumbnail(for: id) != nil)
        store.clear()
        #expect(reload().items.isEmpty)
        #expect(store.images.thumbnail(for: id) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: images.path) == [])
    }

    @Test
    func testTrimmingAndLoadingRemoveUnreferencedImages() throws {
        store.add(try capture())
        let id = try #require(store.items.first?.id)
        for index in 0..<50 { store.add("\(index)") }
        store.setMaximumCount(50)
        #expect(store.images.pngData(for: id) == nil)
        let orphan = UUID()
        #expect(store.images.store(id: orphan, capture: try capture()))
        #expect(reload().images.pngData(for: orphan) == nil)
    }

    @Test
    func testImageDecodeThumbnailAndInvalidData() throws {
        let image = try capture()
        #expect(image.pixelWidth == 256)
        #expect(image.pixelHeight == 64)
        let thumbnail = try #require(NSBitmapImageRep(data: image.thumbnailData))
        #expect(thumbnail.pixelsWide == 128)
        #expect(thumbnail.pixelsHigh == 32)
        #expect(ClipboardImage.read(from: pasteboard)?.digest == image.digest)
        pasteboard.setData(Data("不是图片".utf8), forType: .png)
        #expect(ClipboardImage.read(from: pasteboard) == nil)
    }

    @Test
    func testClipboardImageAndTextPriority() throws {
        _ = try capture()
        for (text, expected) in [("中文正文", false), ("hello world", false), ("https://example.com/image", true), ("照片.PNG", true), ("  \n", true)] {
            pasteboard.setString(text, forType: .string)
            #expect(ClipboardImage.prefersImage(in: pasteboard) == expected)
        }
    }

    @Test
    func testMonitorIgnoresExistingContentsOwnWritesAndSensitiveTypes() {
        pasteboard.setString("启动前", forType: .string)
        let monitor = ClipboardMonitor(store: store, pasteboard: pasteboard)
        monitor.readIfChanged()
        #expect(store.items.isEmpty)
        pasteboard.clearContents()
        pasteboard.setString("新内容", forType: .string)
        monitor.readIfChanged()
        let original = store.items
        monitor.readIfChanged()
        #expect(store.items == original)
        pasteboard.clearContents()
        pasteboard.setString("自己写回", forType: .string)
        monitor.acknowledgeOwnWrite(changeCount: pasteboard.changeCount)
        monitor.readIfChanged()
        #expect(store.items == original)
        for type in ["TransientType", "ConcealedType", "AutoGeneratedType"] {
            pasteboard.clearContents()
            pasteboard.setString("敏感内容", forType: .string)
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.\(type)"))
            monitor.readIfChanged()
            #expect(store.items == original)
        }
        pasteboard.clearContents()
        pasteboard.setString("恢复采集", forType: .string)
        monitor.readIfChanged()
        #expect(store.items.first?.text == "恢复采集")
    }

    @Test
    func testOversizedImageIsRejected() throws {
        let image = ImageCapture(
            pngData: Data(repeating: 0, count: 20 * 1024 * 1024 + 1),
            thumbnailData: Data(), pixelWidth: 1, pixelHeight: 1, digest: "oversized"
        )
        store.add(image)
        #expect(store.items.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("images").path
        ) == [])
    }

    @Test
    func testMonitorCapturesImagesAndPreservesTextBody() throws {
        let monitor = ClipboardMonitor(store: store, pasteboard: pasteboard)
        let image = try capture()
        monitor.readIfChanged()
        #expect(store.items.first?.imageDigest == image.digest)
        // 开启一次新的剪贴板写入，使 changeCount 递增，再同时提供图片与文字。
        _ = try capture()
        pasteboard.setString("中文正文", forType: .string)
        monitor.readIfChanged()
        #expect(store.items.first?.kind == .text)
        #expect(store.items.first?.text == "中文正文")
        #expect(store.items.count == 2)
    }

    @Test
    func testLegacyTextHistoryDecoding() throws {
        let id = UUID()
        let data = Data("[{\"id\":\"\(id)\",\"text\":\"旧文本\",\"createdAt\":0}]".utf8)
        let item = try #require(JSONDecoder().decode([HistoryItem].self, from: data).first)
        #expect(item.kind == .text)
        #expect(item.id == id)
        #expect(item.imageDigest == nil)
    }
}
