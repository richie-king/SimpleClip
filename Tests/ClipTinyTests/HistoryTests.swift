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

    @Test
    func testSingleItemDeletion() throws {
        store.add("项1")
        store.add("项2")
        let img = try capture()
        store.add(img)
        let imgId = try #require(store.items.first(where: { $0.isImage })?.id)
        #expect(store.items.count == 3)
        #expect(store.images.pngData(for: imgId) != nil)

        // 删除图片
        store.delete(id: imgId)
        #expect(store.items.count == 2)
        #expect(store.images.pngData(for: imgId) == nil)
        #expect(reload().items == store.items)

        // 删除文本
        let textId = store.items[0].id
        store.delete(id: textId)
        #expect(store.items.count == 1)
        #expect(reload().items == store.items)
    }

    @Test
    func testItemPinningAndTrimPreservation() {
        for i in 1...10 {
            store.add("条目 \(i)")
        }
        #expect(store.items.count == 10)

        // 置顶较早的条目 2 和条目 5
        let item2 = store.items.first(where: { $0.text == "条目 2" })!
        let item5 = store.items.first(where: { $0.text == "条目 5" })!
        store.togglePin(id: item2.id)
        store.togglePin(id: item5.id)

        // 验证置顶条目排在最前面
        #expect(store.items[0].isPinned)
        #expect(store.items[1].isPinned)
        #expect(!store.items[2].isPinned)

        // 调整容量上限为 5，验证即使容量收缩，置顶条目绝对不会被丢弃
        store.setMaximumCount(50) // 确保初始
        for i in 11...60 {
            store.add("新条目 \(i)")
        }
        store.setMaximumCount(50)
        #expect(store.items.contains(where: { $0.id == item2.id && $0.isPinned }))
        #expect(store.items.contains(where: { $0.id == item5.id && $0.isPinned }))

        // 取消置顶
        store.togglePin(id: item2.id)
        #expect(store.items.first(where: { $0.id == item2.id })?.isPinned == false)
    }

    @Test
    func testFileHistoryCaptureAndHandling() throws {
        let tempFile = directory.appendingPathComponent("test-document.txt")
        try "ClipTiny 文件内容测试".write(to: tempFile, atomically: true, encoding: .utf8)

        store.addFile(url: tempFile)
        let item = try #require(store.items.first)
        #expect(item.kind == .file)
        #expect(item.text == "test-document.txt")
        #expect(item.filePath == tempFile.path)
        #expect(item.byteCount != nil && (item.byteCount ?? 0) > 0)

        let reloaded = reload()
        #expect(reloaded.items.first?.kind == .file)
        #expect(reloaded.items.first?.filePath == tempFile.path)
    }

    @Test
    func testPinyinSearchAndMultiWordAndMatching() {
        let text1 = "网址导航与剪贴板管理器"
        #expect(PinyinHelper.pinyinInitials(for: "网址") == "wz")
        #expect(PinyinHelper.pinyinFull(for: "网址") == "wangzhi")

        // 拼音首字母匹配
        #expect(PinyinHelper.queryMatches("wz", text: text1))
        #expect(PinyinHelper.queryMatches("jtb", text: text1))

        // 全拼匹配
        #expect(PinyinHelper.queryMatches("wangzhi", text: text1))

        // 多词空格拆分 AND 匹配
        #expect(PinyinHelper.queryMatches("wz 管理器", text: text1))
        #expect(PinyinHelper.queryMatches("剪贴板 导航", text: text1))
        #expect(!PinyinHelper.queryMatches("剪贴板 音乐", text: text1))
    }

    @Test
    func testSensitiveMasker() {
        let githubToken = "ghp_1234567890abcdef1234567890abcdef1234"
        #expect(SensitiveMasker.isSensitive(githubToken))
        let maskedGh = SensitiveMasker.mask(githubToken)
        #expect(maskedGh.hasPrefix("ghp_"))
        #expect(maskedGh.contains("••••••••"))
        #expect(!maskedGh.contains("abcdef1234567890"))

        let openAIKey = "sk-proj-abc123def456xyz789012345"
        #expect(SensitiveMasker.isSensitive(openAIKey))
        let maskedOpenAI = SensitiveMasker.mask(openAIKey)
        #expect(maskedOpenAI.hasPrefix("sk-"))
        #expect(maskedOpenAI.contains("••••••••"))

        let awsKey = "AKIA1234567890ABCDEF"
        #expect(SensitiveMasker.isSensitive(awsKey))
        let maskedAWS = SensitiveMasker.mask(awsKey)
        #expect(maskedAWS.hasPrefix("AKIA"))
        #expect(maskedAWS.contains("••••••••"))

        let normalText = "普通日常文本，无任何敏感信息"
        #expect(!SensitiveMasker.isSensitive(normalText))
        #expect(SensitiveMasker.mask(normalText) == normalText)
    }

    @Test
    func testAppBlacklist() {
        let monitor = ClipboardMonitor(store: store, pasteboard: pasteboard, defaults: defaults)
        #expect(!monitor.isAppBlacklisted("com.1password.1password"))

        defaults.set(["com.1password.1password"], forKey: ClipboardMonitor.blacklistDefaultsKey)
        #expect(monitor.isAppBlacklisted("com.1password.1password"))
    }

    @Test
    func testDebouncedSaveAndFlushSync() throws {
        let debouncedDir = directory.appendingPathComponent("debounced")
        let debouncedStore = HistoryStore(
            directory: debouncedDir,
            key: key,
            defaults: defaults,
            debounceInterval: 2.0
        )
        debouncedStore.add("防抖测试文本")
        let file = debouncedDir.appendingPathComponent("history.enc")
        // 由于设置了 2 秒防抖，立即在磁盘上应该还未写入
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // 执行同步 flush
        debouncedStore.flushSync()
        #expect(FileManager.default.fileExists(atPath: file.path))
        let encrypted = try Data(contentsOf: file)
        let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key)
        let items = try JSONDecoder().decode([HistoryItem].self, from: plaintext)
        #expect(items.first?.text == "防抖测试文本")
    }

    @Test
    func testPlainTextFormatting() {
        let messy = "   \n\n\n第一段内容\n\n\n\n\n第二段内容\n\n   "
        let formatted = PasteService.formatPlainText(messy)
        #expect(formatted == "第一段内容\n\n第二段内容")
    }
}

