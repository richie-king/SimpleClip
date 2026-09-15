import AppKit
import ApplicationServices

struct Failure: Error, CustomStringConvertible { let description: String }
func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(description: message) }
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[2])
let receiverURL = URL(fileURLWithPath: CommandLine.arguments[3])
let suite = "ClipTinyDesktopTests.\(UUID().uuidString)"
let board = NSPasteboard.general
let snapshot = (board.pasteboardItems ?? []).map { item in
    item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
}
let originals = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.local.ClipTiny" }
let originalURLs = originals.compactMap(\.bundleURL)
let originalFrontmost = NSWorkspace.shared.frontmostApplication
var fixture: NSRunningApplication?
var receiver: NSRunningApplication?
var results: [String] = []
var skipped: [String] = []
func pause(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.03))) }
}
func wait(_ description: String, timeout: Double = 5, condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        pause(0.05)
    }
    throw Failure(description: "等待超时：\(description)")
}
func state(_ name: String) -> [String: Any] {
    guard let data = try? Data(contentsOf: root.appendingPathComponent(name + ".json")),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return json
}
func launch(_ url: URL, arguments: [String] = []) throws -> NSRunningApplication {
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = arguments
    var answer: NSRunningApplication?
    var failure: Error?
    var finished = false
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
        answer = app; failure = error; finished = true
    }
    try wait("启动 \(url.lastPathComponent)", timeout: 15) { finished }
    if let failure { throw failure }
    guard let answer else { throw Failure(description: "应用未启动") }
    return answer
}
func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
    pause(0.15)
}
func type(_ text: String) {
    let units = Array(text.utf16)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
        event.flags = []
        units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress!) }
        event.post(tap: .cghidEventTap)
    }
    pause(0.25)
}
func focusReceiver(_ mode: String = "text") throws {
    try (mode + UUID().uuidString).write(to: root.appendingPathComponent("receiver-command"), atomically: true, encoding: .utf8)
    receiver?.activate()
    try wait("接收窗口置前") { NSWorkspace.shared.frontmostApplication?.processIdentifier == receiver?.processIdentifier }
    try wait("接收器焦点") { (state("receiver")["nontext"] as? Bool) == (mode == "nontext") }
    pause(0.15)
}
func hotkey() { key(9, flags: [.maskCommand, .maskShift]) }
func items() -> [[String: String]] { state("fixture")["items"] as? [[String: String]] ?? [] }
func visible() -> Bool { state("fixture")["visible"] as? Bool ?? false }
func pass(_ description: String) { results.append(description); print("PASS: " + description); fflush(stdout) }
func restore() {
    fixture?.terminate(); receiver?.terminate()
    try? wait("测试进程退出") { (fixture?.isTerminated ?? true) && (receiver?.isTerminated ?? true) }
    // 只恢复本次测试前的剪贴板内容；不把用户内容写入报告或磁盘。
    board.clearContents()
    let restored = snapshot.map { pairs -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in pairs { item.setData(data, forType: type) }
        return item
    }
    if !restored.isEmpty { board.writeObjects(restored) }
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    for url in originalURLs { _ = try? launch(url) }
    originalFrontmost?.activate()
}
var exitCode: Int32 = 0
var errorText: String?
do {
    try check(AXIsProcessTrusted() && CGPreflightPostEventAccess(), "桌面驱动缺少辅助功能或事件发送权限")
    for app in originals { try check(app.terminate(), "无法暂时退出原 ClipTiny") }
    try wait("原 ClipTiny 退出") { originals.allSatisfy(\.isTerminated) }
    fixture = try launch(fixtureURL, arguments: [root.path, suite])
    try wait("测试应用就绪") { state("fixture")["policy"] != nil }
    let canAutoPaste = state("fixture")["accessibility"] as? Bool == true
    if !canAutoPaste { skipped.append("测试应用未获辅助功能授权：自动文本/图片粘贴与授权后的非文本目标保护") }
    try check(state("fixture")["policy"] as? Int == NSApplication.ActivationPolicy.accessory.rawValue, "应用应为菜单栏模式")
    try check(!visible(), "启动后不应自动显示历史窗口")
    pass("启动为菜单栏应用且历史窗口隐藏")
    receiver = try launch(receiverURL, arguments: [root.path])
    try focusReceiver()
    let marker = "ClipTiny 桌面测试 " + UUID().uuidString
    board.clearContents(); board.setString(marker, forType: .string)
    try wait("采集文本") { items().first?["text"] == marker }
    hotkey(); try wait("全局快捷键打开") { visible() }
    hotkey(); try wait("全局快捷键关闭") { !visible() }
    try focusReceiver()
    hotkey(); try wait("全局快捷键再次打开") { visible() }
    pass("真实 ⌘⇧V 连续打开、关闭、再次打开")
    let initialIDs = items().compactMap { $0["id"] }
    key(36)
    if !canAutoPaste {
        try wait("无授权时关闭窗口") { !visible() }
        pause(1.5)
        try check(state("receiver")["pastes"] as? Int == 0, "无授权时不应自动粘贴")
        try check(board.string(forType: .string) == marker, "无授权时仍应复制文本")
        key(9, flags: .maskCommand)
    }
    try wait("文本粘贴到接收器") { state("receiver")["text"] as? String == marker }
    try check(!visible(), "粘贴后窗口应关闭")
    try check(NSWorkspace.shared.frontmostApplication?.processIdentifier == receiver?.processIdentifier, "粘贴后应回到原应用")
    pause(0.5)
    try check(items().compactMap { $0["id"] } == initialIDs, "自动粘贴不能新增记录或改变顺序")
    pass(canAutoPaste ? "Enter 跨应用自动粘贴文本、恢复前台、历史不重复" : "无授权 Enter 只复制、恢复原应用，手动 ⌘V 粘贴成功且历史不重复")
    try focusReceiver()
    let pastes = state("receiver")["pastes"] as? Int ?? -1
    hotkey(); try wait("打开复制窗口") { visible() }
    key(8, flags: .maskCommand)
    try wait("复制关闭窗口") { !visible() }
    pause(0.5)
    try check(board.string(forType: .string) == marker, "⌘C 应复制选中内容")
    try check(state("receiver")["pastes"] as? Int == pastes, "⌘C 不应自动粘贴")
    key(9, flags: .maskCommand)
    try wait("手动粘贴") { state("receiver")["text"] as? String == marker }
    pass("⌘C 只复制并关闭，回到原应用后 ⌘V 可粘贴")
    try focusReceiver("nontext")
    let beforeNonText = state("receiver")["pastes"] as? Int ?? -1
    hotkey(); try wait("打开非文本目标测试") { visible() }
    key(36)
    try wait("非文本目标关闭窗口") { !visible() }
    pause(1.8)
    try check(state("receiver")["pastes"] as? Int == beforeNonText, "非文本目标不应自动粘贴")
    try check(board.string(forType: .string) == marker, "非文本目标仍应复制内容")
    if canAutoPaste { pass("非文本按钮获得焦点时不自动粘贴，内容仍已复制") }
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.bitmapData!.initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    let png = bitmap.representation(using: .png, properties: [:])!
    board.clearContents(); board.setData(png, forType: .png)
    try wait("采集图片") { items().first?["kind"] == "image" }
    let imageIDs = items().compactMap { $0["id"] }
    try focusReceiver()
    hotkey(); try wait("打开图片记录") { visible() }
    key(36)
    if !canAutoPaste {
        try wait("无授权图片复制后关闭窗口") { !visible() }
        try wait("图片复制后恢复接收器前台") { NSWorkspace.shared.frontmostApplication?.processIdentifier == receiver?.processIdentifier }
        pause(0.2)
        key(9, flags: .maskCommand)
    }
    try wait("图片跨应用粘贴") { (state("receiver")["images"] as? Int ?? 0) > 0 }
    try check(board.data(forType: .png) != nil && board.data(forType: .tiff) != nil, "图片写回应同时提供 PNG/TIFF")
    pause(0.5)
    try check(items().compactMap { $0["id"] } == imageIDs, "图片粘贴不能新增或重排历史")
    try check((state("receiver")["text"] as? String)?.contains("\u{fffc}") == true, "接收器应实际插入图片附件")
    pass(canAutoPaste ? "图片自动粘贴为附件、提供 PNG/TIFF、历史不重复" : "无授权图片复制后手动粘贴为附件、提供 PNG/TIFF、历史不重复")
    try focusReceiver()
    hotkey(); try wait("打开搜索测试") { visible() && state("fixture")["key"] as? Bool == true }
    try wait("搜索前应用激活") { NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture?.processIdentifier }
    pause(0.3)
    key(3, flags: .maskCommand); type("不存在的测试内容")
    try wait("真实键盘搜索空结果") { state("fixture")["rows"] as? Int == 0 }
    key(53); try wait("Esc 清空搜索") { state("fixture")["rows"] as? Int == 2 && visible() }
    key(53); try wait("Esc 关闭窗口") { !visible() }
    pass("真实键盘 ⌘F 输入搜索、第一次 Esc 清空、第二次关闭")
    fixture?.terminate()
    try wait("隔离应用退出") { fixture?.isTerminated == true }
    try FileManager.default.removeItem(at: root.appendingPathComponent("fixture.json"))
    fixture = try launch(fixtureURL, arguments: [root.path, suite])
    try wait("隔离应用重启加载历史") { items().compactMap { $0["id"] } == imageIDs }
    pass("实际进程退出并重启后文本和图片记录恢复")
} catch {
    exitCode = 1; errorText = String(describing: error)
    print("FAIL: \(error)")
}
restore()
let report: [String: Any] = ["passed": results, "skipped": skipped, "error": errorText as Any? ?? NSNull(), "date": ISO8601DateFormatter().string(from: Date())]
if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
    try? data.write(to: root.appendingPathComponent("results.json"), options: .atomic)
}
exit(exitCode)
