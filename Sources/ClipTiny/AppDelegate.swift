import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: HistoryStore
    private let defaults: UserDefaults

    override convenience init() {
        self.init(store: HistoryStore(), defaults: .standard)
    }

    init(store: HistoryStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        super.init()
    }

    private var monitor: ClipboardMonitor!
    private var hotKey: GlobalHotKey!
    private var historyWindow: HistoryWindowController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        historyWindow = HistoryWindowController(store: store, defaults: defaults)
        monitor = ClipboardMonitor(store: store, defaults: defaults)
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
        store.flushSync()
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

        // 1. 保留条目数
        let maximumCount = NSMenuItem(title: "保留条目数", action: nil, keyEquivalent: "")
        let maximumCountMenu = NSMenu()
        for count in HistoryStore.availableMaximumCounts {
            let item = NSMenuItem(
                title: "\(count) 条",
                action: #selector(setMaximumCount(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = count
            item.state = count == store.maximumCount ? .on : .off
            maximumCountMenu.addItem(item)
        }
        maximumCount.submenu = maximumCountMenu
        menu.addItem(maximumCount)

        // 2. 窗口弹出位置偏好
        let positionItem = NSMenuItem(title: "窗口弹出位置", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        let modes: [(WindowPositionMode, String)] = [
            (.centerAndRemember, "居中 / 记忆位置"),
            (.followMouse, "跟随鼠标指针"),
            (.followFocusedElement, "跟随输入光标")
        ]
        let currentMode = defaults.string(forKey: "WindowPositionMode") ?? WindowPositionMode.centerAndRemember.rawValue
        for (mode, label) in modes {
            let item = NSMenuItem(
                title: label,
                action: #selector(setWindowPositionMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode.rawValue == currentMode ? .on : .off
            positionMenu.addItem(item)
        }
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)

        // 3. 应用黑名单设置
        let blacklistMenuItem = NSMenuItem(title: "排除应用", action: nil, keyEquivalent: "")
        let blacklistMenu = NSMenu()
        let excludeCurrent = NSMenuItem(
            title: "排除当前前台应用",
            action: #selector(excludeCurrentFrontApp),
            keyEquivalent: ""
        )
        excludeCurrent.target = self
        blacklistMenu.addItem(excludeCurrent)

        let clearBlacklist = NSMenuItem(
            title: "清空已排除应用",
            action: #selector(clearBlacklistApps),
            keyEquivalent: ""
        )
        clearBlacklist.target = self
        blacklistMenu.addItem(clearBlacklist)
        blacklistMenuItem.submenu = blacklistMenu
        menu.addItem(blacklistMenuItem)

        // 4. 开机自启动能力 (SMAppService)
        let launchAtLogin = NSMenuItem(
            title: "开机启动",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)

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

    @objc private func setMaximumCount(_ sender: NSMenuItem) {
        store.setMaximumCount(sender.tag)
        sender.menu?.items.forEach {
            $0.state = $0.tag == store.maximumCount ? .on : .off
        }
    }

    @objc private func setWindowPositionMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        defaults.set(mode, forKey: "WindowPositionMode")
        sender.menu?.items.forEach {
            $0.state = ($0.representedObject as? String) == mode ? .on : .off
        }
    }

    @objc private func excludeCurrentFrontApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else { return }
        var blacklist = defaults.stringArray(forKey: ClipboardMonitor.blacklistDefaultsKey) ?? []
        if !blacklist.contains(bundleId) {
            blacklist.append(bundleId)
            defaults.set(blacklist, forKey: ClipboardMonitor.blacklistDefaultsKey)
        }
    }

    @objc private func clearBlacklistApps() {
        defaults.removeObject(forKey: ClipboardMonitor.blacklistDefaultsKey)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                sender.state = .off
            } else {
                try service.register()
                sender.state = .on
            }
        } catch {
            NSLog("ClipTiny 切换开机启动状态失败：%@", error.localizedDescription)
            sender.state = service.status == .enabled ? .on : .off
        }
    }

    @objc private func quit() {
        store.flushSync()
        NSApp.terminate(nil)
    }
}
