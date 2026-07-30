import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HistoryStore()
    private var monitor: ClipboardMonitor!
    private var hotKey: GlobalHotKey!
    private var historyWindow: HistoryWindowController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        historyWindow = HistoryWindowController(store: store)
        monitor = ClipboardMonitor(store: store)
        historyWindow.onPasteboardWrite = { [weak self] changeCount in
            self?.monitor.acknowledgeOwnWrite(changeCount: changeCount)
        }
        hotKey = GlobalHotKey { [weak self] in
            self?.historyWindow.toggle()
        }
        monitor.start()
        configureStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "ClipTiny"
        )

        let menu = NSMenu()
        let open = NSMenuItem(
            title: "打开剪贴板历史  ⇧⌘V",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let clear = NSMenuItem(
            title: "清空历史",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clear.target = self
        menu.addItem(clear)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 ClipTiny",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func openHistory() {
        historyWindow.show()
    }

    @objc private func clearHistory() {
        store.clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
