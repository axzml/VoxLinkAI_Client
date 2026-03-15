//
//  ASRService.swift
//  VoxLink
//
//  语音识别服务 - 协调音频捕获和 ASR 客户端
//  BYOK 模式：用户自备阿里云 API Key 直连
//

import AVFoundation
import Combine
import Foundation

/// ASR 状态
enum ASRState {
    case idle
    case recording
    case processing
}

/// 转录结果
struct TranscriptionResult {
    let isSuccess: Bool
    let text: String?              // 最终输出（用于输入到编辑框）
    let originalText: String?      // 原始转录（用于历史记录）
    let polished: String?          // 润色结果
    let error: String?
    let isCancelled: Bool          // 是否被用户取消

    static func success(originalText: String, finalText: String, polished: String? = nil) -> TranscriptionResult {
        TranscriptionResult(
            isSuccess: true,
            text: finalText,
            originalText: originalText,
            polished: polished,
            error: nil,
            isCancelled: false
        )
    }

    static func failure(error: String) -> TranscriptionResult {
        TranscriptionResult(isSuccess: false, text: nil, originalText: nil, polished: nil, error: error, isCancelled: false)
    }

    static func cancelled() -> TranscriptionResult {
        TranscriptionResult(isSuccess: false, text: nil, originalText: nil, polished: nil, error: nil, isCancelled: true)
    }
}

/// ASR 客户端协议
protocol ASRStreamingClient {
    var currentFullTranscript: String { get }
    var onTranscript: ((ASRTranscriptResult) -> Void)? { get set }
    func start() async throws
    func sendAudio(_ pcmData: Data)
    func stop() async throws -> String
    func cancel()
}

// MARK: - AliyunASRClient 扩展以符合协议
extension AliyunASRClient: ASRStreamingClient {}

/// 语音识别服务
@MainActor
final class ASRService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var state: ASRState = .idle
    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var errorMessage: String?

    // MARK: - Callbacks

    var onStateChange: ((ASRState) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onComplete: ((TranscriptionResult) -> Void)?

    // MARK: - Private Properties

    private let audioCapture = AudioCapture()
    private var audioLevelCancellable: AnyCancellable?
    private var pcmDataCancellable: AnyCancellable?

    /// 当前使用的 ASR 客户端
    private var asrClient: ASRStreamingClient?

    /// BYOK 模式下的 API Key
    private var currentSessionApiKey: String?

    /// 音量级别发布者
    var audioLevelPublisher: AnyPublisher<CGFloat, Never> {
        audioCapture.audioLevelPublisher
    }

    // MARK: - Initialization

    init() {
        print("[ASRService] Initialized (BYOK mode)")

        // 预热音频引擎
        Task { @MainActor in
            self.audioCapture.prepare()
            print("[ASRService] Audio capture prepared")
        }
    }

    // MARK: - Public Methods

    /// 开始录音
    func startRecording() async {
        guard !isRunning else {
            print("[ASRService] Already recording")
            return
        }

        // 检查配额（使用 QuotaService）
        let quotaResult = QuotaService.shared.canStartRecording()
        guard quotaResult.isAllowed else {
            let errorMsg = quotaResult.errorMessage ?? "配额不足"
            print("[ASRService] Quota check failed: \(errorMsg)")
            self.errorMessage = errorMsg
            onComplete?(.failure(error: errorMsg))
            return
        }

        // 立即设置状态，防止快速按键时状态不同步
        self.isRunning = true
        self.state = .recording
        self.partialTranscript = ""
        self.errorMessage = nil
        onStateChange?(.recording)

        do {
            try audioCapture.startCapture(accumulateBuffer: false)
            print("[ASRService] Started recording (streaming)")

            // 启动转录
            await startStreaming()
        } catch {
            print("[ASRService] Failed to start recording: \(error)")
            self.errorMessage = error.localizedDescription
            self.isRunning = false
            self.state = .idle
            onStateChange?(.idle)
        }
    }

    /// 停止录音并处理
    func stopRecording() async {
        guard isRunning else {
            print("[ASRService] stopRecording called but not running")
            return
        }

        // 获取音频数据
        let pcmData = audioCapture.stopCapture()
        self.isRunning = false
        self.state = .processing
        onStateChange?(.processing)

        print("[ASRService] Stopped recording, processing \(pcmData.count) bytes")

        // 结束转录
        await finishStreaming(pcmData)
    }

    /// 切换录音状态
    func toggleRecording() async {
        if isRunning {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    /// 取消录音
    func cancelRecording() {
        guard isRunning else { return }

        _ = audioCapture.stopCapture()

        // 取消客户端
        asrClient?.cancel()
        asrClient = nil

        // 取消音频数据订阅
        pcmDataCancellable?.cancel()
        pcmDataCancellable = nil

        self.isRunning = false
        self.state = .idle
        self.partialTranscript = ""
        onStateChange?(.idle)

        // 通知取消
        onComplete?(.cancelled())

        print("[ASRService] Recording cancelled by user")
    }

    // MARK: - Private Methods - Streaming

    /// 启动转录（BYOK 流式模式）
    private func startStreaming() async {
        let settings = SettingsStore.shared

        // 重置状态
        currentSessionApiKey = nil

        // 检查是否有自备 API Key
        guard let apiKey = APIKeyStore.shared.aliyunASRAPIKey, !apiKey.isEmpty else {
            print("[ASRService] No API Key configured")
            self.errorMessage = "请先配置阿里云 API Key"
            self.isRunning = false
            self.state = .idle
            onStateChange?(.idle)
            onComplete?(.failure(error: "请先配置阿里云 API Key"))
            return
        }

        // BYOK 模式：直连阿里云（流式）
        print("[ASRService] Using BYOK mode, direct to Aliyun (streaming)...")
        currentSessionApiKey = apiKey

        let mode: AliyunASRMode = settings.aliyunRegion == "singapore" ? .singapore : .server
        let client = AliyunASRClient(apiKey: apiKey, mode: mode)
        asrClient = client

        // 设置实时转录回调
        asrClient?.onTranscript = { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let client = self.asrClient else { return }
                let fullTranscript = client.currentFullTranscript
                self.partialTranscript = fullTranscript
                self.onPartialTranscript?(fullTranscript)
            }
        }

        // 订阅音频数据流（实时发送）
        pcmDataCancellable = audioCapture.pcmDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pcmData in
                self?.asrClient?.sendAudio(pcmData)
            }

        do {
            try await asrClient?.start()
            print("[ASRService] BYOK streaming started")
        } catch {
            print("[ASRService] Failed to start BYOK streaming: \(error)")
            self.errorMessage = error.localizedDescription
            self.isRunning = false
            self.state = .idle
            onStateChange?(.idle)
            onComplete?(.failure(error: error.localizedDescription))
            asrClient = nil
        }
    }

    /// 结束转录
    private func finishStreaming(_ pcmData: Data) async {
        print("[ASRService] finishStreaming called with \(pcmData.count) bytes")

        // 取消音频数据订阅
        pcmDataCancellable?.cancel()
        pcmDataCancellable = nil

        do {
            guard let client = asrClient else {
                print("[ASRService] No client to finish")
                self.state = .idle
                onStateChange?(.idle)
                onComplete?(.failure(error: "转录客户端未初始化"))
                return
            }
            let transcript = try await client.stop()

            asrClient = nil

            guard !transcript.isEmpty else {
                print("[ASRService] Empty transcript")
                self.state = .idle
                onStateChange?(.idle)
                onComplete?(.failure(error: "未检测到语音"))
                return
            }

            print("[ASRService] Transcription: \(transcript)")

            // AI 处理
            var finalOutput = transcript
            var polishedText: String? = nil

            if let apiKey = currentSessionApiKey {
                print("[ASRService] Processing with AI (BYOK)...")
                let aiClient = AliyunAIClient(apiKey: apiKey)
                do {
                    let aiResult = try await aiClient.process(text: transcript)
                    if aiResult.success {
                        finalOutput = aiResult.finalOutput
                        polishedText = aiResult.polished
                        print("[ASRService] AI result - intent: \(aiResult.intent ?? "NONE")")
                    }
                } catch {
                    print("[ASRService] AI processing failed: \(error)")
                }
            }

            // 返回结果
            let result = TranscriptionResult.success(
                originalText: transcript,
                finalText: finalOutput,
                polished: polishedText
            )

            // 更新本地配额状态（仅 UI 展示）
            // 真实的配额扣除由 Go 后端在 ASR 流程中完成
            // (16kHz, 16bit, mono -> 32000 bytes/sec)
            let durationSeconds = Int(ceil(Double(pcmData.count) / 32000.0))
            if durationSeconds > 0 {
                QuotaService.shared.updateLocalDurationUsage(durationSeconds: durationSeconds)
            }

            self.state = .idle
            onStateChange?(.idle)
            onComplete?(result)

        } catch {
            print("[ASRService] Processing failed: \(error)")
            self.state = .idle
            onStateChange?(.idle)
            onComplete?(.failure(error: error.localizedDescription))
            asrClient = nil
        }
    }

    /// 检查 API 连接
    func checkAPIConnection() async -> Bool {
        guard let apiKey = APIKeyStore.shared.aliyunASRAPIKey, !apiKey.isEmpty else {
            return false
        }
        return apiKey.hasPrefix("sk-")
    }
}
