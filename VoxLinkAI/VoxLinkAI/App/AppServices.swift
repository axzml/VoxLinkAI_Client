//
//  AppServices.swift
//  VoxLink
//
//  服务容器 - 集中管理所有服务
//

import Combine
import Foundation

/// 集中式服务容器
@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    // MARK: - Services

    /// 语音识别服务
    lazy var asrService: ASRService = {
        print("[AppServices] Creating ASRService")
        return ASRService()
    }()

    /// 快捷键管理器
    lazy var hotkeyManager: GlobalHotkeyManager = {
        print("[AppServices] Creating GlobalHotkeyManager")
        return GlobalHotkeyManager(asrService: self.asrService)
    }()

    /// 文本输入服务
    lazy var typingService: TypingService = {
        print("[AppServices] Creating TypingService")
        return TypingService()
    }()

    /// 悬浮窗管理器
    var overlayManager: OverlayManager {
        OverlayManager.shared
    }

    /// 结果窗口管理器
    var resultWindowManager: ResultWindowManager {
        ResultWindowManager.shared
    }

    // MARK: - Initialization

    private init() {
        print("[AppServices] Service container created")
    }

    /// 初始化所有服务（在 UI 准备好后调用）
    func initializeServices() {
        Task {
            // 触发懒加载
            _ = self.asrService
            _ = self.hotkeyManager
            _ = self.typingService
            _ = self.overlayManager

            // 配置服务间的回调
            self.setupCallbacks()

            print("[AppServices] All services initialized")
        }
    }

    private func setupCallbacks() {
        // ASR 服务状态变化时更新 overlay
        self.asrService.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.handleASRStateChange(state)
            }
        }

        // ASR 有新转录文本时更新 overlay
        self.asrService.onPartialTranscript = { [weak self] text in
            Task { @MainActor in
                self?.overlayManager.updateTranscript(text)
            }
        }

        // ASR 完成时的处理
        self.asrService.onComplete = { [weak self] result in
            Task { @MainActor in
                self?.handleTranscriptionComplete(result)
            }
        }

        // Overlay 取消按钮回调
        self.overlayManager.onCancel = { [weak self] in
            Task { @MainActor in
                self?.asrService.cancelRecording()
            }
        }
    }

    private func handleASRStateChange(_ state: ASRState) {
        switch state {
        case .idle:
            overlayManager.hide()
        case .recording:
            overlayManager.show(mode: .dictation)
            // 连接音频级别到 overlay
            overlayManager.connectAudioLevel(asrService.audioLevelPublisher)
        case .processing:
            overlayManager.setProcessing(true)
        }
    }

    private func handleTranscriptionComplete(_ result: TranscriptionResult) {
        // 处理用户取消的情况
        if result.isCancelled {
            print("[AppServices] Recording was cancelled by user, skipping...")
            // 重置快捷键管理器状态，确保下次按键能正常响应
            hotkeyManager.resetState()
            overlayManager.hide()
            return
        }

        guard result.isSuccess, let text = result.text, !text.isEmpty else {
            // 录音失败或无内容时也重置状态
            hotkeyManager.resetState()
            overlayManager.hide()
            return
        }

        // 保存到历史记录（使用原始转录，而不是最终输出）
        let originalText = result.originalText ?? text
        HistoryStore.shared.add(text: originalText, polished: result.polished)

        // 重置快捷键管理器状态，确保下次按键能正常响应
        hotkeyManager.resetState()

        // 检查是否可以输入到当前应用
        let (canType, appName, reason) = typingService.canTypeToFocusedApp()

        print("[AppServices] Can type: \(canType), app: \(appName ?? "nil"), reason: \(reason ?? "nil")")

        if canType {
            // 尝试自动输入
            typingService.typeText(text) { [weak self] typingResult in
                if typingResult.success {
                    print("[AppServices] Text typed successfully to \(typingResult.targetAppName ?? "unknown")")
                    self?.overlayManager.hide()
                } else {
                    // 输入失败，显示结果窗口
                    print("[AppServices] Typing failed: \(typingResult.error ?? "unknown")")
                    self?.overlayManager.hide()
                    self?.showResultWindow(result: result)
                }
            }
        } else {
            // 无法输入，直接显示结果窗口
            print("[AppServices] Cannot type: \(reason ?? "unknown")")
            overlayManager.hide()
            showResultWindow(result: result)
        }
    }

    private func showResultWindow(result: TranscriptionResult) {
        resultWindowManager.show(result: result, typingService: typingService)
    }
}
