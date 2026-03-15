//
//  GlobalHotkeyManager.swift
//  VoxLink
//
//  全局快捷键监听 - 使用 CGEventTap
//
//  支持两种模式：
//  - 点击模式 (默认，与 Python 版本一致):
//    - 短按快捷键 开始录音
//    - 再短按快捷键 停止录音
//    - 长按快捷键 (>300ms) 取消录音
//  - 按住模式:
//    - 按下快捷键 开始录音
//    - 松开快捷键 停止录音
//

import AppKit
import Foundation

/// 录音器状态
enum RecorderState {
    case idle
    case recording
    case processing
}

/// 全局快捷键管理器
final class GlobalHotkeyManager: @unchecked Sendable {
    // MARK: - Properties

    private weak var asrService: ASRService?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let state = HotkeyState()
    private var isInitialized = false

    // 用于在回调中安全持有 self
    private var selfRetained: Unmanaged<GlobalHotkeyManager>?

    // 长按检测定时器
    private var longPressTimer: DispatchSourceTimer?

    // 权限检查定时器
    private var permissionCheckTimer: Timer?

    // MARK: - Hotkey State

    /// 快捷键状态容器
    ///
    /// - Note: 并发安全设计说明
    ///   - 所有状态属性（isKeyPressed, pressStartTime, recorderState, isLongPressCancelled）
    ///     都通过 `withLock` 方法访问，确保线程安全
    ///   - 外部代码不应直接访问这些属性，必须通过 `withLock` 闭包
    private final class HotkeyState: @unchecked Sendable {
        let lock = NSLock()
        var isKeyPressed = false
        var pressStartTime: Date?
        var recorderState: RecorderState = .idle
        var isLongPressCancelled = false

        /// 线程安全地访问状态
        /// - Parameter block: 状态操作闭包，接收可变的状态字段副本
        /// - Returns: 闭包的返回值
        func withLock<T>(_ block: (inout HotkeyStateFields) -> T) -> T {
            self.lock.lock()
            defer { self.lock.unlock() }
            var fields = HotkeyStateFields(
                isKeyPressed: isKeyPressed,
                pressStartTime: pressStartTime,
                recorderState: recorderState,
                isLongPressCancelled: isLongPressCancelled
            )
            let result = block(&fields)
            self.isKeyPressed = fields.isKeyPressed
            self.pressStartTime = fields.pressStartTime
            self.recorderState = fields.recorderState
            self.isLongPressCancelled = fields.isLongPressCancelled
            return result
        }
    }

    private struct HotkeyStateFields {
        var isKeyPressed: Bool
        var pressStartTime: Date?
        var recorderState: RecorderState
        var isLongPressCancelled: Bool
    }

    // MARK: - Initialization

    init(asrService: ASRService) {
        self.asrService = asrService
        // 立即初始化，不延迟
        DispatchQueue.main.async { [weak self] in
            self?.setupEventTap()
        }
    }

    // MARK: - Event Tap Setup

    private func setupEventTap() {
        // 清理现有的 tap
        self.cleanupEventTap()

        // 检查辅助功能权限
        guard AXIsProcessTrusted() else {
            print("[HotkeyManager] Accessibility permissions not granted, will retry...")
            startPermissionCheckTimer()
            return
        }

        // 权限已授予，停止检查定时器
        stopPermissionCheckTimer()

        // 设置事件掩码
        let eventMask = (1 << CGEventType.keyDown.rawValue)
                      | (1 << CGEventType.keyUp.rawValue)
                      | (1 << CGEventType.flagsChanged.rawValue)

        // ⚠️ 手动内存管理警告 ⚠️
        // CGEvent.tapCreate 的 C 回调无法捕获 Swift 对象，需通过 userInfo 传递指针。
        // 为防止回调执行期间 self 被 ARC 释放，必须手动 retain。
        // 注意：必须在 cleanupEventTap() 中配对调用 release，否则会内存泄漏。
        // 未来优化：可考虑使用更安全的封装方式。
        self.selfRetained = Unmanaged.passRetained(self)

        // 创建事件 tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return GlobalHotkeyManager.handleEventStatic(
                    manager: manager,
                    proxy: proxy,
                    type: type,
                    event: event
                )
            },
            userInfo: selfRetained?.toOpaque()
        ) else {
            // 如果创建失败，释放持有的引用
            selfRetained?.release()
            selfRetained = nil
            print("[HotkeyManager] Failed to create event tap")
            return
        }

        self.eventTap = tap

        // 创建 run loop source
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        // 添加到 run loop
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.isInitialized = true
        print("[HotkeyManager] Event tap created successfully")
    }

    private func cleanupEventTap() {
        // 停止权限检查定时器
        stopPermissionCheckTimer()

        // 取消长按定时器
        cancelLongPressTimer()

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        // 配对释放：与 setupEventTap() 中的 retain 对应
        // 延迟 0.1 秒是为了确保正在执行的回调完成后才释放
        if let retained = selfRetained {
            selfRetained = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                retained.release()
            }
        }
    }

    // MARK: - Long Press Timer

    private func startLongPressTimer() {
        cancelLongPressTimer()

        let thresholdMs = SettingsStore.shared.longPressCancelMs
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(thresholdMs))
        timer.setEventHandler { [weak self] in
            self?.handleLongPressTimeout()
        }
        timer.resume()
        self.longPressTimer = timer
    }

    private func cancelLongPressTimer() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    // MARK: - Permission Check Timer

    /// 启动权限检查定时器（每 2 秒检查一次）
    private func startPermissionCheckTimer() {
        stopPermissionCheckTimer()

        DispatchQueue.main.async {
            self.permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if AXIsProcessTrusted() {
                    print("[HotkeyManager] Accessibility permission granted, setting up event tap...")
                    self.stopPermissionCheckTimer()
                    self.setupEventTap()
                }
            }
            print("[HotkeyManager] Permission check timer started")
        }
    }

    /// 停止权限检查定时器
    private func stopPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    /// 手动重新初始化（供外部调用，例如用户在设置中点击重新授权）
    func reinitialize() {
        setupEventTap()
    }

    private func handleLongPressTimeout() {
        let shouldCancel = state.withLock { fields -> Bool in
            // 只有在录音状态下，长按才触发取消
            if fields.isKeyPressed && fields.recorderState == .recording && !fields.isLongPressCancelled {
                fields.isLongPressCancelled = true
                return true
            }
            return false
        }

        if shouldCancel {
            print("[HotkeyManager] Long press detected, cancelling recording...")
            Task { @MainActor in
                self.cancelRecording()
            }
        }
    }

    // MARK: - Event Handling

    /// 静态回调函数
    private static func handleEventStatic(
        manager: GlobalHotkeyManager,
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // 处理 tap 被禁用的情况（超时、用户输入过多、或权限被撤销）
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                // 检查权限是否仍然有效
                if AXIsProcessTrusted() {
                    print("[HotkeyManager] Event tap disabled, re-enabling...")
                    manager.setupEventTap()
                } else {
                    print("[HotkeyManager] Event tap disabled due to permission loss, starting permission check...")
                    manager.isInitialized = false
                    manager.startPermissionCheckTimer()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let isPressed = manager.isHotkeyPressed(flags: flags)

        manager.handleKeyEvent(isHotKeyPressed: isPressed)

        // 不拦截任何事件，让它们正常传递
        return Unmanaged.passUnretained(event)
    }

    /// 检查配置的快捷键是否被按下（通过 flags 检测 modifier 键状态）
    private func isHotkeyPressed(flags: CGEventFlags) -> Bool {
        let configuredKeyCode = SettingsStore.shared.hotkeyKeyCode

        switch configuredKeyCode {
        case 58, 61: // Option (Left/Right)
            return flags.contains(.maskAlternate)
        case 59, 62: // Control (Left/Right)
            return flags.contains(.maskControl)
        case 55, 54: // Command (Left/Right)
            return flags.contains(.maskCommand)
        case 56, 60: // Shift (Left/Right)
            return flags.contains(.maskShift)
        case 63: // Fn
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }

    private func handleKeyEvent(isHotKeyPressed: Bool) {
        let wasPressed = state.withLock { $0.isKeyPressed }

        // 检测按键状态变化
        if isHotKeyPressed && !wasPressed {
            // 快捷键按下
            let hotkeyName = HotkeyDefinition.displayName(for: SettingsStore.shared.hotkeyKeyCode)
            handleHotkeyPressed(hotkeyName: hotkeyName)
        } else if !isHotKeyPressed && wasPressed {
            // 快捷键释放
            let hotkeyName = HotkeyDefinition.displayName(for: SettingsStore.shared.hotkeyKeyCode)
            handleHotkeyReleased(hotkeyName: hotkeyName)
        }
    }

    private func handleHotkeyPressed(hotkeyName: String) {
        let pressAndHoldMode = SettingsStore.shared.pressAndHoldMode

        state.withLock { fields in
            fields.isKeyPressed = true
            fields.pressStartTime = Date()
        }

        print("[HotkeyManager] \(hotkeyName) pressed, pressAndHoldMode=\(pressAndHoldMode)")

        if pressAndHoldMode {
            // 按住模式：按下立即开始录音
            Task { @MainActor in
                self.startRecording()
            }
        } else {
            // 点击模式：短按触发开始/停止，长按取消
            // 先启动长按检测定时器
            startLongPressTimer()

            // 立即触发开始/停止
            let currentState = state.withLock { $0.recorderState }
            if currentState == .idle {
                // 开始录音
                state.withLock { $0.recorderState = .recording }
                Task { @MainActor in
                    self.startRecording()
                }
            } else if currentState == .recording {
                // 停止录音
                cancelLongPressTimer()
                state.withLock { $0.recorderState = .processing }
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }
    }

    private func handleHotkeyReleased(hotkeyName: String) {
        let pressAndHoldMode = SettingsStore.shared.pressAndHoldMode

        state.withLock { fields in
            fields.isKeyPressed = false
            fields.pressStartTime = nil
        }

        print("[HotkeyManager] \(hotkeyName) released, pressAndHoldMode=\(pressAndHoldMode)")

        if pressAndHoldMode {
            // 按住模式：松开停止录音
            Task { @MainActor in
                self.stopRecording()
            }
        } else {
            // 点击模式：松开时取消长按定时器
            cancelLongPressTimer()
        }
    }

    // MARK: - Recording Control

    @MainActor
    private func startRecording() {
        guard let asrService = self.asrService else { return }
        print("[HotkeyManager] Starting recording")
        Task {
            await asrService.startRecording()
        }
    }

    @MainActor
    private func stopRecording() {
        guard let asrService = self.asrService else { return }
        print("[HotkeyManager] Stopping recording, isRunning=\(asrService.isRunning)")

        // 直接调用 stopRecording，ASRService 内部会检查 isRunning
        Task {
            await asrService.stopRecording()
            // 重置状态
            self.state.withLock { fields in
                fields.recorderState = .idle
                fields.isLongPressCancelled = false
            }
        }
    }

    @MainActor
    private func cancelRecording() {
        guard let asrService = self.asrService else { return }
        if asrService.isRunning {
            print("[HotkeyManager] Cancelling recording")
            asrService.cancelRecording()
        }
        // 重置状态
        self.state.withLock { fields in
            fields.recorderState = .idle
            fields.isLongPressCancelled = false
        }
    }

    /// 重置状态（供外部调用）
    func resetState() {
        cancelLongPressTimer()
        state.withLock { fields in
            fields.recorderState = .idle
            fields.isKeyPressed = false
            fields.pressStartTime = nil
            fields.isLongPressCancelled = false
        }
    }

    // MARK: - Cleanup

    deinit {
        cleanupEventTap()
        print("[HotkeyManager] Deinitialized")
    }
}

// MARK: - Hotkey Definition

/// 快捷键定义
enum HotkeyDefinition: Int, CaseIterable {
    case optionLeft = 58
    case optionRight = 61
    case controlLeft = 59
    case controlRight = 62
    case commandLeft = 55
    case commandRight = 54
    case shiftLeft = 56
    case shiftRight = 60
    case fn = 63

    var keyCode: UInt16 {
        return UInt16(rawValue)
    }

    var displayName: String {
        switch self {
        case .optionLeft, .optionRight:
            return "Option (⌥)"
        case .controlLeft, .controlRight:
            return "Control (⌃)"
        case .commandLeft, .commandRight:
            return "Command (⌘)"
        case .shiftLeft, .shiftRight:
            return "Shift (⇧)"
        case .fn:
            return "Fn"
        }
    }

    var symbol: String {
        switch self {
        case .optionLeft, .optionRight:
            return "⌥"
        case .controlLeft, .controlRight:
            return "⌃"
        case .commandLeft, .commandRight:
            return "⌘"
        case .shiftLeft, .shiftRight:
            return "⇧"
        case .fn:
            return "fn"
        }
    }

    /// 根据 keyCode 获取显示名称
    static func displayName(for keyCode: UInt16) -> String {
        if let def = HotkeyDefinition.allCases.first(where: { $0.keyCode == keyCode }) {
            return def.displayName
        }
        return "Key \(keyCode)"
    }

    /// 根据 keyCode 获取符号
    static func symbol(for keyCode: UInt16) -> String {
        if let def = HotkeyDefinition.allCases.first(where: { $0.keyCode == keyCode }) {
            return def.symbol
        }
        return "⚫︎"
    }

    /// 获取主要的快捷键选项（左右键合并显示）
    static var primaryOptions: [(keyCode: UInt16, displayName: String, symbol: String)] {
        return [
            (58, "Option (⌥)", "⌥"),
            (59, "Control (⌃)", "⌃"),
            (55, "Command (⌘)", "⌘"),
            (56, "Shift (⇧)", "⇧"),
            (63, "Fn", "fn")
        ]
    }
}
