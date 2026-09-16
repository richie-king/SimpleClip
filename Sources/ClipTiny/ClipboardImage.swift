import AppKit
import CryptoKit

/// 一次图片捕获的结果：统一转成 PNG，另外附带列表用的缩略图。
struct ImageCapture {
    let pngData: Data
    let thumbnailData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let digest: String
}

enum ClipboardImage {
    static let thumbnailMaxSide: CGFloat = 128

    private static let maximumSourceBytes = 64 * 1024 * 1024
    private static let readableTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("com.compuserve.gif")
    ]

    /// 剪贴板同时带文字和图片时的取舍：文字是正文就按文字处理，
    /// 文字只是图片的地址或文件名（浏览器里复制图片）才按图片处理。
    static func prefersImage(in pasteboard: NSPasteboard) -> Bool {
        guard pasteboard.availableType(from: readableTypes) != nil else { return false }
        guard
            let text = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return true }
        return looksLikeImageReference(text)
    }

    /// 只认链接和图片文件名。不能用“有没有空格”判断，
    /// 中文正文本来就没有空格。
    private static func looksLikeImageReference(_ text: String) -> Bool {
        guard text.count < 2048, !text.contains(where: \.isWhitespace) else { return false }
        let lowercased = text.lowercased()
        let schemes = ["http://", "https://", "file://", "data:image/"]
        if schemes.contains(where: lowercased.hasPrefix) { return true }
        let extensions = [
            ".png", ".jpg", ".jpeg", ".gif",
            ".tif", ".tiff", ".heic", ".webp", ".bmp"
        ]
        return extensions.contains(where: lowercased.hasSuffix)
    }

    /// 在主线程快速提取原始二进制与类型，避免在主线程执行沉重的图片解码
    static func rawImageData(from pasteboard: NSPasteboard) -> (NSPasteboard.PasteboardType, Data)? {
        guard
            let type = pasteboard.availableType(from: readableTypes),
            let data = pasteboard.data(forType: type),
            data.count <= maximumSourceBytes
        else { return nil }
        return (type, data)
    }

    /// 后台转码与缩略图生成
    static func capture(from data: Data) -> ImageCapture? {
        guard let representation = NSBitmapImageRep(data: data) else { return nil }
        return capture(from: representation)
    }

    static func read(from pasteboard: NSPasteboard) -> ImageCapture? {
        guard let (_, data) = rawImageData(from: pasteboard) else { return nil }
        return capture(from: data)
    }

    private static func capture(from representation: NSBitmapImageRep) -> ImageCapture? {
        guard
            representation.pixelsWide > 0,
            representation.pixelsHigh > 0,
            let png = representation.representation(using: .png, properties: [:]),
            let thumbnail = thumbnailData(from: representation)
        else { return nil }

        let digest = SHA256.hash(data: png)
            .map { String(format: "%02x", $0) }
            .joined()
        return ImageCapture(
            pngData: png,
            thumbnailData: thumbnail,
            pixelWidth: representation.pixelsWide,
            pixelHeight: representation.pixelsHigh,
            digest: digest
        )
    }

    private static func thumbnailData(from representation: NSBitmapImageRep) -> Data? {
        let width = CGFloat(representation.pixelsWide)
        let height = CGFloat(representation.pixelsHigh)
        let scale = min(1, thumbnailMaxSide / max(width, height))
        let size = NSSize(
            width: max(1, (width * scale).rounded()),
            height: max(1, (height * scale).rounded())
        )

        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        target.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        representation.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return target.representation(using: .png, properties: [:])
    }
}
