import AppKit
import CryptoKit
import ApplicationServices

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let suite = CommandLine.arguments[2]
let defaults = UserDefaults(suiteName: suite)!
// 不在自动化运行中弹出系统授权提示，缺少权限时验证只复制的降级行为。
defaults.set(true, forKey: "AccessibilityPermissionPrompted")
let store = HistoryStore(directory: root.appendingPathComponent("history"), key: SymmetricKey(data: Data(repeating: 42, count: 32)), defaults: defaults)
let app = NSApplication.shared
let delegate = AppDelegate(store: store, defaults: defaults)
app.delegate = delegate
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
    let window = app.windows.first { $0 is ShortcutPanel }
    let views = window?.contentView.map(descendants) ?? []
    let state: [String: Any] = [
        "visible": window?.isVisible ?? false,
        "key": window?.isKeyWindow ?? false,
        "query": views.compactMap { $0 as? NSSearchField }.first?.stringValue ?? "",
        "rows": views.compactMap { $0 as? NSTableView }.first?.numberOfRows ?? -1,
        "items": store.items.map { ["id": $0.id.uuidString, "text": $0.text, "kind": $0.kind.rawValue] },
        "accessibility": AXIsProcessTrusted(),
        "policy": app.activationPolicy().rawValue
    ]
    if let data = try? JSONSerialization.data(withJSONObject: state) {
        try? data.write(to: root.appendingPathComponent("fixture.json"), options: .atomic)
    }
}
app.run()
