import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let menu = NSMenu()
let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
let editMenu = NSMenu(title: "编辑")
editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
editItem.submenu = editMenu
menu.addItem(editItem)
app.mainMenu = menu
final class Receiver: NSTextView {
    var pasteCount = 0
    var imagePasteCount = 0
    override func paste(_ sender: Any?) {
        pasteCount += 1
        if NSPasteboard.general.data(forType: .png) != nil { imagePasteCount += 1 }
        super.paste(sender)
    }
}
final class NonTextButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
}
let window = NSWindow(contentRect: NSRect(x: 200, y: 240, width: 520, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "ClipTiny 自动化粘贴接收器"
let editor = Receiver(frame: NSRect(x: 10, y: 50, width: 490, height: 210))
editor.isRichText = true
editor.importsGraphics = true
let button = NonTextButton(title: "非文本控件", target: nil, action: nil)
button.frame = NSRect(x: 10, y: 10, width: 180, height: 30)
window.contentView?.addSubview(editor)
window.contentView?.addSubview(button)
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(editor)
app.activate()
var lastCommand = ""
let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
    if let command = try? String(contentsOf: root.appendingPathComponent("receiver-command"), encoding: .utf8), command != lastCommand {
        lastCommand = command
        if command.hasPrefix("nontext") { window.makeFirstResponder(button) }
        else { editor.string = ""; window.makeFirstResponder(editor) }
    }
    let state: [String: Any] = ["text": editor.string, "pastes": editor.pasteCount, "images": editor.imagePasteCount, "nontext": window.firstResponder === button]
    if let data = try? JSONSerialization.data(withJSONObject: state) {
        try? data.write(to: root.appendingPathComponent("receiver.json"), options: .atomic)
    }
}
app.run()
