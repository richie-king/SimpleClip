import AppKit
import CryptoKit
import Testing
@testable import ClipTiny

/// 需要图形登录会话；显式开启，避免普通测试或 CI 意外激活窗口。
@MainActor
private final class UIWindowFixture {
    private let directory: URL
    private let suite: String
    private let defaults: UserDefaults
    private let store: HistoryStore
    private let controller: HistoryWindowController
    private let panel: NSWindow

    init() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "ClipTinyUITests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = HistoryStore(directory: directory, key: SymmetricKey(size: .bits256), defaults: defaults)
        store.add("中文自动化测试")
        store.add("Hello UI Automation")
        store.add("https://example.com")
        controller = HistoryWindowController(store: store, defaults: defaults)
        panel = try #require(controller.window)
        controller.show()
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func cleanUp() {
        panel.orderOut(nil)
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func views(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { views($0) }
    }

    private func view<T: NSView>(_ type: T.Type) throws -> T {
        let root = try #require(panel.contentView)
        return try #require(views(root).compactMap { $0 as? T }.first)
    }

    private func button(_ title: String) throws -> NSButton {
        let root = try #require(panel.contentView)
        return try #require(views(root).compactMap { $0 as? NSButton }.first { $0.title == title })
    }

    private func search(_ text: String) throws {
        let field = try view(NSSearchField.self)
        panel.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    private func command(_ text: String, keyCode: UInt16) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: keyCode
        ))
        #expect(panel.performKeyEquivalent(with: event))
    }

    private func editorCommand(_ selector: Selector) throws {
        let field = try view(NSSearchField.self)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.doCommand(by: selector)
    }

    func searchAndEmptyState() throws {
        let table = try view(NSTableView.self)
        #expect(panel.isVisible)
        #expect(table.numberOfRows == 3)
        try search("hello")
        #expect(table.numberOfRows == 1)
        let textViews = views(try #require(panel.contentView)).compactMap { $0 as? NSTextView }
        #expect(textViews.contains { !$0.isFieldEditor && $0.string == "Hello UI Automation" })
        try search("中文")
        #expect(table.numberOfRows == 1)
        try search("不存在的记录")
        #expect(table.numberOfRows == 0)
        #expect(table.selectedRow == -1)
        #expect(!(try button("粘贴")).isEnabled)
        let labels = views(try #require(panel.contentView)).compactMap { $0 as? NSTextField }
        #expect(labels.contains { $0.stringValue == "没有找到相关记录" && !$0.isHiddenOrHasHiddenAncestor })
    }

    func categoryControlsAndShortcuts() throws {
        let table = try view(NSTableView.self)
        let filter = try view(NSSegmentedControl.self)
        try command("3", keyCode: 20)
        #expect(filter.selectedSegment == 2)
        #expect(table.numberOfRows == 0)
        try command("2", keyCode: 19)
        #expect(filter.selectedSegment == 1)
        #expect(table.numberOfRows == 3)
        try search("hello")
        #expect(table.numberOfRows == 1)
        filter.selectedSegment = 2
        #expect(filter.sendAction(filter.action, to: filter.target))
        #expect(table.numberOfRows == 0)
        try command("1", keyCode: 18)
        #expect(table.numberOfRows == 1)
    }

    func keyboardSelectionFocusAndRefresh() throws {
        let table = try view(NSTableView.self)
        let field = try view(NSSearchField.self)
        #expect(table.selectedRow == 0)
        try editorCommand(#selector(NSResponder.moveDown(_:)))
        #expect(table.selectedRow == 1)
        store.add("新复制内容")
        #expect(table.selectedRow == 2)
        try editorCommand(#selector(NSResponder.moveUp(_:)))
        #expect(table.selectedRow == 1)
        try editorCommand(#selector(NSResponder.insertTab(_:)))
        #expect(panel.firstResponder === table)
        try command("f", keyCode: 3)
        #expect(panel.firstResponder === field.currentEditor())
    }

    func escapeCloseButtonAndToggle() throws {
        try search("hello")
        try editorCommand(#selector(NSResponder.cancelOperation(_:)))
        #expect(panel.isVisible)
        #expect(try view(NSSearchField.self).stringValue.isEmpty)
        #expect(try view(NSTableView.self).numberOfRows == 3)
        try editorCommand(#selector(NSResponder.cancelOperation(_:)))
        #expect(!panel.isVisible)
        controller.toggle()
        #expect(panel.isVisible)
        controller.toggle()
        #expect(!panel.isVisible)
        controller.toggle()
        try button("esc").performClick(nil)
        #expect(!panel.isVisible)
    }

    func windowFramePersistsAcrossReopen() throws {
        var frame = panel.frame
        frame.size = NSSize(width: 900, height: 560)
        panel.setFrame(frame, display: true)
        let expected = panel.frame
        try command("w", keyCode: 13)
        #expect(!panel.isVisible)
        controller.show()
        #expect(panel.frame == expected)
        let restored = HistoryWindowController(store: store, defaults: defaults)
        #expect(restored.window?.frame == expected)
        restored.window?.orderOut(nil)
    }

    func appearanceAndMinimumSizeLayout() throws {
        let table = try view(NSTableView.self)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            panel.appearance = NSAppearance(named: appearance)
            panel.setFrame(NSRect(origin: panel.frame.origin, size: panel.minSize), display: true)
            let root = try #require(panel.contentView)
            root.layoutSubtreeIfNeeded()
            #expect(!table.hasAmbiguousLayout)
            #expect(table.visibleRect.width > 0)
            #expect(table.visibleRect.height > 0)
            let field = try view(NSSearchField.self)
            #expect(field.bounds.width > 100)
            let paste = try button("粘贴")
            #expect(paste.bounds.width > 0)
            #expect(root.bounds.contains(paste.convert(paste.bounds, to: root)))
        }
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CLIPTINY_UI_TESTS"] == "1"))
struct UITests {
    @Test
    func searchAndEmptyState() async throws {
        try await MainActor.run {
            let fixture = try UIWindowFixture()
            defer { fixture.cleanUp() }
            try fixture.searchAndEmptyState()
        }
    }

    @Test
    func categoryControlsAndShortcuts() async throws {
        try await MainActor.run {
            let fixture = try UIWindowFixture()
            defer { fixture.cleanUp() }
            try fixture.categoryControlsAndShortcuts()
        }
    }

    @Test
    func keyboardSelectionFocusAndRefresh() async throws {
        try await MainActor.run {
            let fixture = try UIWindowFixture()
            defer { fixture.cleanUp() }
            try fixture.keyboardSelectionFocusAndRefresh()
        }
    }

    @Test
    func escapeCloseButtonAndToggle() async throws {
        try await MainActor.run {
            let fixture = try UIWindowFixture()
            defer { fixture.cleanUp() }
            try fixture.escapeCloseButtonAndToggle()
        }
    }

    @Test
    func windowFramePersistsAcrossReopen() async throws {
        try await MainActor.run {
            let fixture = try UIWindowFixture()
            defer { fixture.cleanUp() }
            try fixture.windowFramePersistsAcrossReopen()
        }
    }

    @Test
    func appearanceAndMinimumSizeLayout() async throws {
        try await MainActor.run {
            let fixture = try UIWindowFixture()
            defer { fixture.cleanUp() }
            try fixture.appearanceAndMinimumSizeLayout()
        }
    }

}
