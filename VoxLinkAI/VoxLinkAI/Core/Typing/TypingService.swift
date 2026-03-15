//
//  TypingService.swift
//  VoxLink
//
//  文本输入服务 - 使用 CGEvent 直接输入文字
//

import AppKit
import ApplicationServices
import Foundation

/// 文本输入结果
struct TypingResult {
    let success: Bool
    let error: String?
    let targetAppName: String?

    static func success(appName: String? = nil) -> TypingResult {
        TypingResult(success: true, error: nil, targetAppName: appName)
    }

    static func failure(error: String, appName: String? = nil) -> TypingResult {
        TypingResult(success: false, error: error, targetAppName: appName)
    }
}

/// 文本输入服务
final class TypingService {
    // MARK: - Properties

    private var isTyping = false

    // MARK: - Public Methods

    /// 检测当前焦点应用是否可以接收文本输入
    func canTypeToFocusedApp() -> (canType: Bool, appName: String?, reason: String?) {
        guard AXIsProcessTrusted() else {
            return (false, nil, "没有辅助功能权限")
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return (false, nil, "没有焦点应用")
        }

        let appName = frontmostApp.localizedName ?? "未知应用"

        if frontmostApp.bundleIdentifier == "com.apple.finder" {
            return (false, appName, "Finder 不支持文本输入")
        }

        if frontmostApp.bundleIdentifier?.contains("VoxLinkAI") == true {
            return (false, appName, "不能输入到 VoxLink AI 自身")
        }

        // 检测焦点元素是否是文本输入区域
        let (isEditable, role) = checkFocusedElementIsEditable()
        print("[TypingService] Focused element check - role: \(role ?? "nil"), isEditable: \(isEditable)")

        if isEditable {
            return (true, appName, nil)
        }

        // 回退策略：已知使用自定义渲染引擎、AX 检测不可靠的文本编辑器
        // 这些应用的焦点元素通常返回 AXWindow 而非内部的文本编辑区域
        if isKnownTextInputApp(bundleIdentifier: frontmostApp.bundleIdentifier) {
            print("[TypingService] ✓ Fallback: Known text input app: \(appName) (\(frontmostApp.bundleIdentifier ?? ""))")
            return (true, appName, nil)
        }

        return (false, appName, "当前焦点不在文本输入区域 (role: \(role ?? "unknown"))")
    }

    /// 已知接受文本输入的应用（AX 检测可能不准确时的回退名单）
    /// 包含两类：1) 自定义渲染引擎导致 AX 识别失败的应用  2) 主要用途就是文本编辑的应用
    private func isKnownTextInputApp(bundleIdentifier: String?) -> Bool {
        guard let bundleId = bundleIdentifier else { return false }

        // ── 完整 Bundle ID 匹配 ──
        let knownApps: Set<String> = [
            // --- 代码 / 文本编辑器 ---
            "com.sublimetext.2",
            "com.sublimetext.3",
            "com.sublimetext.4",
            "com.github.atom",                          // Atom
            "com.panic.Nova",                           // Nova
            "com.barebones.bbedit",                     // BBEdit
            "com.coteditor.CotEditor",                  // CotEditor
            "com.macromates.TextMate",                  // TextMate
            "com.macromates.TextMate.preview",
            "org.vim.MacVim",                           // MacVim
            "com.qvacua.VimR",                          // VimR
            "com.apple.dt.Xcode",                       // Xcode
            "abnerworks.Typora",                        // Typora
            "com.uranusjr.macdown",                     // MacDown
            "com.electron.marktext",                    // Mark Text

            // --- Microsoft Office ---
            "com.microsoft.Word",                       // Word
            "com.microsoft.Excel",                      // Excel
            "com.microsoft.Powerpoint",                 // PowerPoint
            "com.microsoft.Outlook",                    // Outlook
            "com.microsoft.onenote.mac",                // OneNote

            // --- Apple 自带 ---
            "com.apple.TextEdit",                       // 文本编辑
            "com.apple.Notes",                          // 备忘录
            "com.apple.mail",                           // 邮件
            "com.apple.iWork.Pages",                    // Pages
            "com.apple.iWork.Numbers",                  // Numbers
            "com.apple.iWork.Keynote",                  // Keynote
            "com.apple.reminders",                      // 提醒事项
            "com.apple.Terminal",                       // 终端

            // --- 终端 ---
            "com.googlecode.iterm2",                    // iTerm2
            "dev.warp.Warp-Stable",                     // Warp
            "co.zeit.hyper",                            // Hyper
            "com.github.wez.wezterm",                   // WezTerm
            "net.kovidgoyal.kitty",                     // Kitty
            "com.mitchellh.ghostty",                    // Ghostty

            // --- 即时通讯 / 社交 ---
            "com.tencent.xinWeChat",                    // 微信
            "com.tencent.qq",                           // QQ
            "com.alibaba.DingTalkMac",                  // 钉钉
            "com.tencent.WeWorkMac",                    // 企业微信
            "com.bytedance.lark",                       // 飞书 (Lark)
            "com.electron.lark",                        // 飞书 (旧版 Electron)
            "com.apple.MobileSMS",                      // iMessage
            "com.tinyspeck.slackmacgap",                // Slack
            "com.hnc.Discord",                          // Discord
            "ru.keepcoder.Telegram",                    // Telegram
            "org.whispersystems.signal-desktop",        // Signal

            // --- 笔记 / 知识管理 ---
            "com.electron.obsidian",                    // Obsidian (Electron)
            "md.obsidian",                              // Obsidian (原生)
            "notion.id",                                // Notion
            "com.craft.craft",                          // Craft
            "com.logseq.logseq",                        // Logseq
            "com.bear-writer.bear",                     // Bear
            "com.ulyssesapp.mac",                       // Ulysses
            "pro.writer.mac",                           // iA Writer
            "com.omnigroup.OmniOutliner5",              // OmniOutliner
            "com.happenapps.Quill",                     // Quill (Draft)
            "com.agiletortoise.Drafts-OSX",             // Drafts

            // --- 专业写作 / 出版 ---
            "com.literatureandlatte.scrivener3",        // Scrivener
            "org.libreoffice.script",                   // LibreOffice
            "com.kingsoft.wpsoffice.mac",               // WPS Office

            // --- 数据库 / API 工具 ---
            "com.sequel-pro.sequel-pro",                // Sequel Pro
            "com.tinyapp.TablePlus",                    // TablePlus
            "com.postmanlabs.mac",                      // Postman
        ]

        if knownApps.contains(bundleId) {
            return true
        }

        // ── 前缀匹配（覆盖同系列应用的不同版本号）──
        let knownPrefixes: [String] = [
            "com.sublimetext.",                         // Sublime Text 全系列
            "com.microsoft.",                           // Microsoft 全系列
            "com.jetbrains.",                           // JetBrains 全系列 (IntelliJ, PyCharm, WebStorm, GoLand...)
            "com.google.android.studio",                // Android Studio
            "com.tencent.",                             // 腾讯全系列
            "com.alibaba.",                             // 阿里全系列
            "com.bytedance.",                           // 字节全系列
        ]

        if knownPrefixes.contains(where: { bundleId.hasPrefix($0) }) {
            return true
        }

        // ── 包含关键字匹配（兜底：名字中含有明确文本编辑含义的应用）──
        let editorKeywords: [String] = [
            "vscode", "visual-studio-code",             // VS Code 各发行版
            "cursor",                                   // Cursor (AI 编辑器)
            "codium",                                   // VSCodium
            "windsurf",                                 // Windsurf
            "zed",                                      // Zed 编辑器
        ]

        let lowerBundleId = bundleId.lowercased()
        return editorKeywords.contains { lowerBundleId.contains($0) }
    }

    /// 检测当前焦点元素是否是可编辑的文本输入区域（多策略检测）
    private func checkFocusedElementIsEditable() -> (isEditable: Bool, role: String?) {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard result == .success, let focusedElementRef = focusedElementRef else {
            print("[TypingService] Failed to get focused element: \(result.rawValue)")
            return (false, nil)
        }

        var element = unsafeBitCast(focusedElementRef, to: AXUIElement.self)

        // 获取元素角色 (AXRole)
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        var role = roleRef as? String

        print("[TypingService] Checking element - role: \(role ?? "nil")")

        // 预处理：如果焦点元素是容器（AXWindow / AXGroup 等），尝试解析更深层的真实焦点元素
        // 某些应用（如 Sublime Text）的 system-wide 焦点查询只返回窗口级别
        let containerRoles: Set<String> = [
            "AXWindow", "AXGroup", "AXScrollArea", "AXSplitGroup", "AXLayoutArea",
        ]
        if let currentRole = role, containerRoles.contains(currentRole) {
            if let resolved = resolveDeepFocusedElement(from: element) {
                element = resolved
                var newRoleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &newRoleRef)
                let newRole = newRoleRef as? String
                print("[TypingService] Resolved deeper element: \(currentRole) -> \(newRole ?? "nil")")
                role = newRole
            }
        }

        // 策略 1: 明确的文本输入角色（这些角色几乎一定是可编辑的）
        let directTextInputRoles: Set<String> = [
            "AXTextArea",       // 多行文本编辑区（TextEdit, Notes, Terminal, VS Code 等）
            "AXTextField",      // 单行文本输入框
            "AXComboBox",       // 带输入框的下拉框
            "AXSearchField",    // 搜索框
        ]

        if let role = role, directTextInputRoles.contains(role) {
            print("[TypingService] ✓ Strategy 1: Direct text input role match: \(role)")
            return (true, role)
        }

        // 策略 2: 检查 AXEditable 属性
        var editableRef: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRef)
        if editableResult == .success, let isEditable = editableRef as? Bool, isEditable {
            print("[TypingService] ✓ Strategy 2: AXEditable attribute is true")
            return (true, role)
        }

        // 策略 3: 检查 AXValue 是否可设置（对于非标准角色的输入区域最可靠）
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable)
        if settableResult == .success && isSettable.boolValue {
            // 排除非文本类的可设置控件（slider, checkbox 等也有可设置的 AXValue）
            let nonTextSettableRoles: Set<String> = [
                "AXSlider", "AXCheckBox", "AXRadioButton",
                "AXPopUpButton", "AXMenuButton", "AXDisclosureTriangle",
                "AXIncrementor", "AXColorWell", "AXProgressIndicator",
            ]
            if let role = role, nonTextSettableRoles.contains(role) {
                print("[TypingService] ✗ Strategy 3: AXValue is settable but role \(role) is non-text control")
            } else {
                print("[TypingService] ✓ Strategy 3: AXValue is settable, role: \(role ?? "nil")")
                return (true, role)
            }
        }

        // 策略 4: 对于 AXWebArea（浏览器网页区域），需要深入检查内部焦点元素
        if role == "AXWebArea" {
            let (webEditable, innerRole) = checkWebAreaFocusedElement(element)
            if webEditable {
                print("[TypingService] ✓ Strategy 4: Web area has editable focused element: \(innerRole ?? "nil")")
                return (true, innerRole ?? role)
            } else {
                print("[TypingService] ✗ Strategy 4: Web area has no editable focused element (inner: \(innerRole ?? "nil"))")
                return (false, role)
            }
        }

        // 策略 5: 检查 subrole 是否暗示可编辑
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String

        let editableSubroles: Set<String> = [
            "AXSearchField",
            "AXSecureTextField",
            "AXPlainText",
            "AXRichText",
        ]

        if let subrole = subrole, editableSubroles.contains(subrole) {
            print("[TypingService] ✓ Strategy 5: Editable subrole: \(subrole)")
            return (true, role)
        }

        // 策略 6: 检查是否支持 kAXSelectedTextAttribute（能选择文本通常意味着是文本输入区域）
        var selectedTextRef: CFTypeRef?
        let selectedTextResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        if selectedTextResult == .success {
            // 额外检查：排除只读文本区域（支持选择但不支持编辑）
            var valueSettable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
            var selectedTextSettable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedTextSettable)

            if valueSettable.boolValue || selectedTextSettable.boolValue {
                print("[TypingService] ✓ Strategy 6: Supports selected text and is settable")
                return (true, role)
            }
        }

        print("[TypingService] ✗ No editable element detected, role: \(role ?? "nil"), subrole: \(subrole ?? "nil")")
        return (false, role)
    }

    /// 从容器元素（AXWindow / AXGroup 等）中解析出更深层的真实焦点元素
    /// 有些应用的 system-wide 焦点查询只返回窗口，需要通过应用级查询或容器级查询获取内部焦点
    private func resolveDeepFocusedElement(from container: AXUIElement) -> AXUIElement? {
        // 方法 A: 从容器本身获取 focusedUIElement
        var childFocusRef: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(
            container,
            kAXFocusedUIElementAttribute as CFString,
            &childFocusRef
        )
        if childResult == .success, let ref = childFocusRef {
            let child = unsafeBitCast(ref, to: AXUIElement.self)
            var childRoleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRoleRef)
            let childRole = childRoleRef as? String
            // 只有当子元素比容器更具体时才使用
            let containerRoles: Set<String> = ["AXWindow", "AXGroup", "AXScrollArea", "AXSplitGroup", "AXLayoutArea"]
            if let childRole = childRole, !containerRoles.contains(childRole) {
                print("[TypingService] Resolved via container's focusedUIElement: \(childRole)")
                return child
            }
        }

        // 方法 B: 通过应用 PID 创建 AXUIElement，查询应用级焦点
        var pid: pid_t = 0
        AXUIElementGetPid(container, &pid)
        if pid > 0 {
            let appElement = AXUIElementCreateApplication(pid)
            var appFocusRef: CFTypeRef?
            let appResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &appFocusRef
            )
            if appResult == .success, let ref = appFocusRef {
                let appFocus = unsafeBitCast(ref, to: AXUIElement.self)
                var appFocusRoleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(appFocus, kAXRoleAttribute as CFString, &appFocusRoleRef)
                let appFocusRole = appFocusRoleRef as? String
                let containerRoles: Set<String> = ["AXWindow", "AXGroup", "AXScrollArea", "AXSplitGroup", "AXLayoutArea"]
                if let appFocusRole = appFocusRole, !containerRoles.contains(appFocusRole) {
                    print("[TypingService] Resolved via application's focusedUIElement: \(appFocusRole)")
                    return appFocus
                }
            }
        }

        print("[TypingService] Could not resolve deeper focused element from container")
        return nil
    }

    /// 检查 AXWebArea 内部的焦点元素是否是可编辑的（用于浏览器检测）
    private func checkWebAreaFocusedElement(_ webArea: AXUIElement) -> (isEditable: Bool, role: String?) {
        // 获取 web area 内部的焦点元素
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            webArea,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard result == .success, let focusedRef = focusedRef else {
            // 无法获取内部焦点，说明网页中没有焦点元素
            return (false, nil)
        }

        let focusedElement = unsafeBitCast(focusedRef, to: AXUIElement.self)

        // 获取内部焦点元素的角色
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleRef)
        let innerRole = roleRef as? String

        print("[TypingService] Web area inner focused element - role: \(innerRole ?? "nil")")

        // 如果内部焦点仍然是 AXWebArea 本身，说明不在输入框中
        if innerRole == "AXWebArea" || innerRole == nil {
            return (false, innerRole)
        }

        // 检查内部焦点元素是否是文本输入类型
        let textInputRoles: Set<String> = [
            "AXTextArea", "AXTextField", "AXComboBox", "AXSearchField",
        ]

        if let innerRole = innerRole, textInputRoles.contains(innerRole) {
            return (true, innerRole)
        }

        // 检查内部焦点元素的 AXEditable
        var editableRef: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(focusedElement, "AXEditable" as CFString, &editableRef)
        if editableResult == .success, let isEditable = editableRef as? Bool, isEditable {
            return (true, innerRole)
        }

        // 检查内部元素的 AXValue 是否可设置
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(focusedElement, kAXValueAttribute as CFString, &isSettable)
        if settableResult == .success && isSettable.boolValue {
            return (true, innerRole)
        }

        // 检查 subrole
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focusedElement, kAXSubroleAttribute as CFString, &subroleRef)
        if let subrole = subroleRef as? String {
            let editableSubroles: Set<String> = [
                "AXSearchField", "AXSecureTextField", "AXPlainText", "AXRichText",
            ]
            if editableSubroles.contains(subrole) {
                return (true, innerRole)
            }
        }

        // 检查是否支持 selectedText（contentEditable 区域通常支持）
        var selectedTextRef: CFTypeRef?
        let selectedTextResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        if selectedTextResult == .success {
            return (true, innerRole)
        }

        return (false, innerRole)
    }

    /// 输入文本到当前应用
    func typeText(_ text: String, targetPID: pid_t? = nil, completion: @escaping (TypingResult) -> Void) {
        guard !text.isEmpty else {
            completion(.failure(error: "文本为空"))
            return
        }
        guard !isTyping else {
            completion(.failure(error: "正在输入中"))
            return
        }

        isTyping = true

        // 在后台线程执行
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                DispatchQueue.main.async {
                    self?.isTyping = false
                }
            }

            // 尝试直接输入
            let (success, appName) = self?.insertTextDirectly(text, targetPID: targetPID) ?? (false, nil)

            DispatchQueue.main.async {
                if success {
                    completion(.success(appName: appName))
                } else {
                    completion(.failure(error: "输入失败", appName: appName))
                }
            }
        }
    }

    // MARK: - Private Methods

    /// 每个 CGEvent 可携带的最大 UTF-16 字符数
    private static let maxCharsPerEvent = 20

    /// 输入文本（多策略，含剪贴板回退）
    private func insertTextDirectly(_ text: String, targetPID: pid_t?) -> (Bool, String?) {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName

        // 策略 1: CGEvent postToPid（分块发送，适用于短文本）
        if let pid = targetPID, pid > 0 {
            if sendUnicodeStringChunked(text, toPID: pid) {
                print("[TypingService] ✓ Strategy 1: CGEvent postToPid succeeded")
                return (true, appName)
            }
        }

        // 策略 2: CGEvent HID tap（分块发送）
        if sendUnicodeStringViaHIDChunked(text) {
            print("[TypingService] ✓ Strategy 2: CGEvent HID tap succeeded")
            return (true, appName)
        }

        // 策略 3: 剪贴板粘贴（最可靠的方式，适用于所有支持 Cmd+V 的应用）
        if insertViaClipboardPaste(text) {
            print("[TypingService] ✓ Strategy 3: Clipboard paste succeeded")
            return (true, appName)
        }

        print("[TypingService] ✗ All insertion strategies failed")
        return (false, appName)
    }

    /// 分块通过 CGEvent.postToPid 发送 Unicode 字符串
    private func sendUnicodeStringChunked(_ text: String, toPID pid: pid_t) -> Bool {
        let utf16Array = Array(text.utf16)
        let chunkSize = Self.maxCharsPerEvent

        for startIndex in stride(from: 0, to: utf16Array.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, utf16Array.count)
            let chunk = Array(utf16Array[startIndex..<endIndex])

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                return false
            }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)

            keyDown.postToPid(pid)
            keyUp.postToPid(pid)

            // 分块之间加微小延迟，让目标应用处理
            if endIndex < utf16Array.count {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        return true
    }

    /// 分块通过 CGEvent HID tap 发送 Unicode 字符串
    private func sendUnicodeStringViaHIDChunked(_ text: String) -> Bool {
        let utf16Array = Array(text.utf16)
        let chunkSize = Self.maxCharsPerEvent

        for startIndex in stride(from: 0, to: utf16Array.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, utf16Array.count)
            let chunk = Array(utf16Array[startIndex..<endIndex])

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else {
                return false
            }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            if endIndex < utf16Array.count {
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
        return true
    }

    /// 通过剪贴板 + Cmd+V 粘贴文本（最可靠的方式）
    private func insertViaClipboardPaste(_ text: String) -> Bool {
        // 在主线程操作剪贴板
        var pasteboardReady = false
        DispatchQueue.main.sync {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboardReady = pasteboard.setString(text, forType: .string)
        }

        guard pasteboardReady else { return false }

        // 短暂延迟确保剪贴板数据就绪
        Thread.sleep(forTimeInterval: 0.05)

        // 模拟 Cmd+V 按键
        let source = CGEventSource(stateID: .combinedSessionState)

        // V 键的虚拟键码是 0x09 (9)
        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }

        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand

        cmdVDown.post(tap: .cghidEventTap)
        cmdVUp.post(tap: .cghidEventTap)

        return true
    }

    // MARK: - Utility Methods

    /// 获取当前焦点应用的 PID
    static func getFocusedAppPID() -> pid_t? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard result == .success, let focusedElementRef = focusedElementRef else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }

        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }

        let element = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        return pid > 0 ? pid : NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}
