import AppKit
import ApplicationServices

enum FocusedElementTextStatus {
    case textInput
    case nonText
    case unavailable
}

enum PasteService {
    private static let accessibilityPromptedKey = "AccessibilityPermissionPrompted"

    /// 检查并请求辅助功能权限
    static func accessibilityAutomationAllowed(defaults: UserDefaults) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard !defaults.bool(forKey: accessibilityPromptedKey) else {
            return false
        }

        defaults.set(true, forKey: accessibilityPromptedKey)
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 检测当前焦点是否为可输入文本的控件
    static func focusedElementTextStatus() -> FocusedElementTextStatus {
        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(),
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success,
            let value = focused,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return .unavailable }

        let element = value as! AXUIElement

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue {
            return .textInput
        }

        var selectedRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success {
            return .textInput
        }

        var role: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXRoleAttribute as CFString,
                &role
            ) == .success,
            let name = role as? String
        else { return .unavailable }
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(name) {
            return .textInput
        }

        let nonTextRoles: Set<String> = [
            "AXButton", "AXCheckBox", "AXRadioButton", "AXMenuItem",
            "AXStaticText", "AXImage", "AXList", "AXTable", "AXOutline",
            "AXBrowser", "AXScrollArea", "AXToolbar", "AXWindow", "AXSheet",
            "AXDialog", "AXDesktop", "AXSplitGroup"
        ]
        return nonTextRoles.contains(name) ? .nonText : .unavailable
    }

    /// 等待光标/焦点就绪后注入 ⌘V
    static func pasteWhenCursorAvailable(attemptsLeft: Int) {
        let status = focusedElementTextStatus()
        switch status {
        case .textInput:
            postPasteShortcut()
        case .nonText, .unavailable:
            guard attemptsLeft > 1 else {
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if case .unavailable = status,
                   frontmostPID != ProcessInfo.processInfo.processIdentifier {
                    postPasteShortcut()
                }
                return
            }
            retryPaste(attemptsLeft: attemptsLeft)
        }
    }

    private static func retryPaste(attemptsLeft: Int) {
        guard attemptsLeft > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            pasteWhenCursorAvailable(attemptsLeft: attemptsLeft - 1)
        }
    }

    /// 发送 ⌘V 按键事件
    static func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: true
        ),
              let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 9,
            keyDown: false
        ) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    /// 纯文本格式清理（去除多余首尾空白，合并超过两个连续换行）
    static func formatPlainText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: "\n{3,}", options: []) else {
            return trimmed
        }
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        return regex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "\n\n")
    }
}
