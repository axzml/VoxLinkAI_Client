//
//  OverlayManager.swift
//  VoxLink
//
//  悬浮窗口管理器 - 支持 Glassmorphism 设计
//

import AppKit
import Combine
import SwiftUI

/// 悬浮窗口管理器
@MainActor
final class OverlayManager {
    static let shared = OverlayManager()

    // MARK: - Properties

    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private let overlayState = OverlayState.shared

    private var audioLevelCancellable: AnyCancellable?
    private var isShowing = false

    // 防抖：避免频繁更新导致抖动
    private var lastUpdateWidth: CGFloat = 0
    private var sizeUpdateWorkItem: DispatchWorkItem?
    private let sizeUpdateDebounceInterval: TimeInterval = 0.15

    /// 取消录音的回调
    var onCancel: (() -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 显示悬浮窗
    func show(mode: OverlayMode = .dictation) {
        guard !isShowing else { return }

        // 创建面板
        createPanelIfNeeded()

        // 重置状态
        overlayState.status = .recording
        overlayState.transcript = ""
        overlayState.audioLevel = 0
        overlayState.startPulsing()

        // 重置尺寸追踪
        lastUpdateWidth = 280

        // 显示面板
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        positionPanel()

        // 动画显示
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel?.animator().alphaValue = 1
        }

        isShowing = true
        print("[OverlayManager] Showing overlay")
    }

    /// 隐藏悬浮窗
    func hide() {
        guard isShowing, let panel = panel else { return }

        // 停止脉动动画
        overlayState.stopPulsing()

        // 取消订阅
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil

        // 动画隐藏
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.overlayState.status = .idle
            self?.isShowing = false
        }

        print("[OverlayManager] Hiding overlay")
    }

    /// 更新转录文本
    func updateTranscript(_ text: String) {
        overlayState.transcript = text
        // 根据文字长度调整面板大小
        updatePanelSize()
    }

    /// 设置处理状态
    func setProcessing(_ processing: Bool, text: String = "处理中...") {
        if processing {
            overlayState.stopPulsing()
            overlayState.status = .processing
            overlayState.processingText = text
        } else {
            overlayState.status = .recording
            overlayState.startPulsing()
        }
        updatePanelSize()
    }

    /// 连接音频级别发布者
    func connectAudioLevel(_ publisher: AnyPublisher<CGFloat, Never>) {
        audioLevelCancellable?.cancel()
        audioLevelCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.overlayState.audioLevel = level
            }
    }

    // MARK: - Private Methods

    private func createPanelIfNeeded() {
        guard panel == nil else { return }

        // 初始大小：单行模式
        let initialWidth: CGFloat = 280
        let initialHeight: CGFloat = 56

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 配置面板
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // 我们用 SwiftUI 的 shadow
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        // 创建 SwiftUI 视图（带取消回调）
        let contentView = OverlayView(state: overlayState) { [weak self] in
            self?.onCancel?()
        }
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)

        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel = panel, let screen = NSScreen.main else { return }

        // 计算位置：屏幕顶部居中
        let screenFrame = screen.frame
        let panelSize = panel.frame.size

        let x = (screenFrame.width - panelSize.width) / 2
        let y = screenFrame.height - panelSize.height - 100 // 距离顶部 100px，避开刘海

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// 根据内容更新面板大小（带防抖，只扩不缩）
    private func updatePanelSize() {
        guard let panel = panel else { return }

        let hasTranscript = !overlayState.transcript.isEmpty
        let isRecording = overlayState.status == .recording

        // 计算目标宽度（渐进式增长）
        let baseWidth: CGFloat = 280
        let maxWidth: CGFloat = 380

        // 根据文字长度计算目标宽度
        let transcriptLen = CGFloat(overlayState.transcript.count)
        let charWidth: CGFloat = 12

        // 目标宽度：基础宽度 + 文字宽度，但有最大限制
        let contentWidth: CGFloat
        if hasTranscript {
            let textWidth = baseWidth + transcriptLen * charWidth + 40
            contentWidth = min(textWidth, maxWidth)
        } else {
            contentWidth = baseWidth
        }

        // 只扩不缩：取当前宽度和内容宽度的最大值
        let targetWidth = max(contentWidth, lastUpdateWidth)

        // 计算目标高度
        let baseHeight: CGFloat = 56
        let targetHeight = (hasTranscript && isRecording) ? 88 : baseHeight

        // 宽度没有变化且高度也没变化，跳过更新
        let widthChange = targetWidth - lastUpdateWidth
        let currentHeight = panel.frame.height
        guard widthChange > 15 || (hasTranscript && lastUpdateWidth == baseWidth) || abs(targetHeight - currentHeight) > 1 else {
            return
        }

        // 取消之前的延迟更新
        sizeUpdateWorkItem?.cancel()

        // 防抖：延迟执行更新
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSizeUpdate(targetWidth: targetWidth, targetHeight: targetHeight)
        }
        sizeUpdateWorkItem = workItem

        // 如果是首次显示文字，立即更新；否则延迟一点
        let delay: TimeInterval = (lastUpdateWidth == baseWidth && hasTranscript) ? 0 : sizeUpdateDebounceInterval
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// 执行实际的尺寸更新
    private func performSizeUpdate(targetWidth: CGFloat, targetHeight: CGFloat) {
        guard let panel = panel else { return }

        lastUpdateWidth = targetWidth

        // 获取当前尺寸
        let currentFrame = panel.frame
        let currentWidth = currentFrame.width

        // 计算新位置（保持居中）
        let newX = currentFrame.origin.x + (currentWidth - targetWidth) / 2
        let newFrame = NSRect(
            x: newX,
            y: currentFrame.origin.y,
            width: targetWidth,
            height: targetHeight
        )

        // panel 和 hostingView 在同一个动画上下文中更新，避免不同步导致闪烁
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
            hostingView?.animator().setFrameSize(NSSize(width: targetWidth, height: targetHeight))
        }
    }
}
