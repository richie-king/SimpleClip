import AppKit

// 按 1024×1024 的坐标系描述图标，每个尺寸都按比例重新矢量绘制，
// 比从大图缩小更清楚。坐标原点在左下角。
private let canvas: CGFloat = 1024

private func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

private func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(
        roundedRect: NSRect(x: x, y: y, width: width, height: height),
        xRadius: radius,
        yRadius: radius
    )
}

private func drawIcon() {
    // 圆角底板，留出 macOS 图标惯用的边距。
    let plate = rounded(100, 100, 824, 824, 185)
    NSGradient(
        starting: color(0x6AA6FF),
        ending: color(0x2F6BE0)
    )?.draw(in: plate, angle: -90)

    // 剪贴板主体
    color(0xFFFFFF).setFill()
    rounded(352, 205, 320, 470, 48).fill()

    // 顶部的夹子，压在主体上边缘
    color(0xB9C2CF).setFill()
    rounded(452, 620, 120, 112, 32).fill()

    // 三条“文字”
    color(0x3B72E0).setFill()
    rounded(412, 530, 200, 26, 13).fill()
    rounded(412, 450, 200, 26, 13).fill()
    rounded(412, 370, 130, 26, 13).fill()
}

private func render(size: Int) -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    representation.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(size) / canvas
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])!
}

// iconutil 需要的十个文件名
private let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

guard CommandLine.arguments.count == 2 else {
    fputs("用法：MakeIcon <输出的 .iconset 目录>\n", stderr)
    exit(EXIT_FAILURE)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for variant in variants {
    let url = directory.appendingPathComponent("\(variant.name).png")
    try! render(size: variant.size).write(to: url)
}
print("wrote \(variants.count) png -> \(directory.path)")
