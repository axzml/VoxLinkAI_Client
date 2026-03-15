//
//  AliyunASRClient.swift
//  VoxLink
//
//  阿里云 ASR 直连客户端 - 通过 WebSocket 直接连接阿里云 DashScope
//  支持实时流式语音识别
//

import Foundation

/// 阿里云 ASR 连接模式
enum AliyunASRMode {
    case server    // 北京地域
    case singapore // 新加坡地域（国际）
}

/// 阿里云 ASR 客户端状态
enum AliyunASRClientState: Equatable {
    case disconnected
    case connecting
    case connected
    case ready         // task-started，可以发送音频
    case processing    // 正在处理
    case finished      // task-finished
    case error(String)
}

/// ASR 转录结果
struct ASRTranscriptResult {
    let text: String
    let isFinal: Bool      // 是否是句子结束
    let beginTime: Int?    // 开始时间 (ms)
    let endTime: Int?      // 结束时间 (ms)
}

/// 阿里云 ASR 直连客户端（实时流式）
/// 类似 Python 的 VoiceSession，支持 start/sendAudio/stop 模式
final class AliyunASRClient: NSObject {
    // MARK: - Configuration

    private let apiKey: String
    private let mode: AliyunASRMode
    private let model: String

    /// WebSocket URL
    private var webSocketURL: URL {
        switch mode {
        case .server:
            return URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference/")!
        case .singapore:
            return URL(string: "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference/")!
        }
    }

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private var taskID: String = ""
    private var state: AliyunASRClientState = .disconnected

    /// 累积的转录结果（句子完成的）
    private var transcriptParts: [String] = []

    /// 当前中间结果
    private var currentInterimText: String = ""

    /// 等待完成的 Continuation
    private var stopContinuation: CheckedContinuation<String, Error>?

    // MARK: - 时间统计

    /// 会话开始时间
    private var sessionStartTime: Date?

    /// WebSocket 连接建立时间
    private var connectedTime: Date?

    /// 发送 run-task 时间
    private var runTaskSentTime: Date?

    /// 收到 task-started 时间
    private var taskStartedTime: Date?

    /// 发送第一段音频时间
    private var firstAudioSentTime: Date?

    /// 收到第一个转录结果时间
    private var firstTranscriptTime: Date?

    /// 发送 finish-task 时间
    private var finishTaskSentTime: Date?

    /// 收到 task-finished 时间
    private var taskFinishedTime: Date?

    /// 音频包计数
    private var audioPacketCount: Int = 0

    // MARK: - Callbacks

    /// 状态变化回调
    var onStateChange: ((AliyunASRClientState) -> Void)?

    /// 实时转录回调（中间结果 + 最终结果）
    var onTranscript: ((ASRTranscriptResult) -> Void)?

    // MARK: - Initialization

    /// 使用 API Key 初始化（自备 Key 模式）
    init(apiKey: String, mode: AliyunASRMode = .server, model: String = "fun-asr-realtime") {
        self.apiKey = apiKey
        self.mode = mode
        self.model = model
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }

    // MARK: - Time Logging Helpers

    private func logTiming(_ event: String) {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestampStr = formatter.string(from: timestamp)

        if let start = sessionStartTime {
            let totalElapsed = timestamp.timeIntervalSince(start)
            print("[⏱️ \(timestampStr)] [AliyunASR] \(event) (距开始: \(String(format: "%.0f", totalElapsed * 1000))ms)")
        } else {
            print("[⏱️ \(timestampStr)] [AliyunASR] \(event)")
        }
    }

    private func printTimingSummary() {
        print("\n[⏱️] ========== BYOK 模式耗时统计 ==========")

        if let start = sessionStartTime {
            print("[⏱️] 会话开始: \(DateFormatter.localizedString(from: start, dateStyle: .none, timeStyle: .medium))")
        }

        if let connected = connectedTime, let start = sessionStartTime {
            let elapsed = connected.timeIntervalSince(start) * 1000
            print("[⏱️] WebSocket 连接建立: +\(String(format: "%.0f", elapsed))ms")
        }

        if let runTask = runTaskSentTime, let start = sessionStartTime {
            let elapsed = runTask.timeIntervalSince(start) * 1000
            print("[⏱️] 发送 run-task: +\(String(format: "%.0f", elapsed))ms")
        }

        if let taskStarted = taskStartedTime, let start = sessionStartTime {
            let elapsed = taskStarted.timeIntervalSince(start) * 1000
            print("[⏱️] 收到 task-started: +\(String(format: "%.0f", elapsed))ms")
        }

        if let firstAudio = firstAudioSentTime, let start = sessionStartTime {
            let elapsed = firstAudio.timeIntervalSince(start) * 1000
            print("[⏱️] 发送第一段音频: +\(String(format: "%.0f", elapsed))ms")
        }

        if let firstTranscript = firstTranscriptTime, let start = sessionStartTime {
            let elapsed = firstTranscript.timeIntervalSince(start) * 1000
            print("[⏱️] 收到第一个转录结果: +\(String(format: "%.0f", elapsed))ms")
        }

        if let finishSent = finishTaskSentTime, let start = sessionStartTime {
            let elapsed = finishSent.timeIntervalSince(start) * 1000
            print("[⏱️] 发送 finish-task: +\(String(format: "%.0f", elapsed))ms")
        }

        if let taskFinished = taskFinishedTime, let start = sessionStartTime {
            let elapsed = taskFinished.timeIntervalSince(start) * 1000
            print("[⏱️] 收到 task-finished: +\(String(format: "%.0f", elapsed))ms")
        }

        // 关键指标
        print("\n[⏱️] ----- 关键指标 -----")

        if let taskStarted = taskStartedTime, let start = sessionStartTime {
            let elapsed = taskStarted.timeIntervalSince(start) * 1000
            print("[⏱️] 🔑 ASR 启动延迟 (开始→task-started): \(String(format: "%.0f", elapsed))ms")
        }

        if let firstAudio = firstAudioSentTime, let firstTranscript = firstTranscriptTime {
            let elapsed = firstTranscript.timeIntervalSince(firstAudio) * 1000
            print("[⏱️] 🔑 首次转录延迟 (音频→转录): \(String(format: "%.0f", elapsed))ms")
        }

        if let start = sessionStartTime, let taskFinished = taskFinishedTime {
            let elapsed = taskFinished.timeIntervalSince(start) * 1000
            print("[⏱️] 🔑 总耗时: \(String(format: "%.0f", elapsed))ms")
        }

        print("[⏱️] 音频包数量: \(audioPacketCount)")
        print("[⏱️] ==============================\n")
    }

    // MARK: - Public Methods (Streaming API)

    /// 开始 ASR 会话（建立 WebSocket 连接）
    func start() async throws {
        // 重置时间统计
        sessionStartTime = Date()
        connectedTime = nil
        runTaskSentTime = nil
        taskStartedTime = nil
        firstAudioSentTime = nil
        firstTranscriptTime = nil
        finishTaskSentTime = nil
        taskFinishedTime = nil
        audioPacketCount = 0

        logTiming("🚀 开始 ASR 会话 (BYOK 直连)")
        print("[AliyunASR] Starting session...")

        // 重置状态
        transcriptParts = []
        currentInterimText = ""
        taskID = generateTaskID()
        state = .connecting
        onStateChange?(.connecting)

        // 创建请求
        var request = URLRequest(url: webSocketURL)
        request.setValue("VoxLinkAI/1.0", forHTTPHeaderField: "user-agent")

        // 设置授权信息（仅支持 API Key 模式）
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // 创建 WebSocket 连接
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        connectedTime = Date()
        logTiming("📡 WebSocket 连接已建立")
        print("[AliyunASR] Connecting to \(webSocketURL.absoluteString)")

        // 开始接收消息
        receiveMessageLoop()

        // 发送 run-task 指令
        try await sendRunTask()

        // 等待 task-started
        try await waitForTaskStarted()

        logTiming("✅ ASR 已准备好")
        print("[AliyunASR] Session started, ready to receive audio")
        state = .ready
        onStateChange?(.ready)
    }

    /// 发送音频数据（实时流式）
    /// - Parameter pcmData: PCM 音频数据 (16kHz, 16-bit, mono)
    func sendAudio(_ pcmData: Data) {
        guard state == .ready || state == .connected else {
            print("[AliyunASR] Warning: sendAudio called in state \(state)")
            return
        }

        // 记录第一段音频发送时间
        if firstAudioSentTime == nil {
            firstAudioSentTime = Date()
            logTiming("🎤 发送第一段音频 (\(pcmData.count) bytes)")
        }

        audioPacketCount += 1

        webSocketTask?.send(.data(pcmData)) { error in
            if let error = error {
                print("[AliyunASR] Error sending audio: \(error)")
            }
        }
    }

    /// 停止 ASR 会话并获取完整转录结果
    /// - Returns: 完整的转录文本
    func stop() async throws -> String {
        logTiming("🛑 停止会话")
        print("[AliyunASR] Stopping session...")

        guard state == .ready || state == .connected else {
            print("[AliyunASR] Already stopped or not started")
            return transcriptParts.joined(separator: " ")
        }

        state = .processing
        onStateChange?(.processing)

        // 发送 finish-task 指令
        sendFinishTask()

        // 等待 task-finished 事件
        let result = try await waitForTaskFinished()

        // 关闭连接
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        onStateChange?(.disconnected)

        // 打印耗时统计
        printTimingSummary()

        print("[AliyunASR] Session stopped, result: \(result)")
        return result
    }

    /// 取消会话
    func cancel() {
        print("[AliyunASR] Cancelling...")
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        onStateChange?(.disconnected)
    }

    /// 获取当前完整转录（包括中间结果）
    var currentFullTranscript: String {
        var parts = transcriptParts
        if !currentInterimText.isEmpty {
            parts.append(currentInterimText)
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Private Methods

    /// 生成任务 ID
    private func generateTaskID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32).lowercased()
    }

    /// 发送 run-task 指令
    private func sendRunTask() async throws {
        runTaskSentTime = Date()
        logTiming("📤 发送 run-task")

        let runTaskMessage: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": [
                    "format": "pcm",
                    "sample_rate": 16000
                ],
                "input": [:]
            ] as [String: Any]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: runTaskMessage)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ASRClientError.encodingError
        }

        print("[AliyunASR] Sending run-task")

        try await webSocketTask?.send(.string(jsonString))
    }

    /// 发送 finish-task 指令
    private func sendFinishTask() {
        finishTaskSentTime = Date()
        logTiming("📤 发送 finish-task")

        let finishTaskMessage: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [:]
            ] as [String: Any]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: finishTaskMessage),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        print("[AliyunASR] Sending finish-task")
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("[AliyunASR] Error sending finish-task: \(error)")
            }
        }
    }

    /// 等待 task-started 事件
    private func waitForTaskStarted() async throws {
        // 状态会在 receiveMessageLoop 中更新
        var retries = 50 // 5 seconds
        while retries > 0 && state == .connecting {
            try await Task.sleep(nanoseconds: 100_000_000)
            retries -= 1
        }

        if state != .ready && state != .connected {
            throw ASRClientError.serverError("Timeout waiting for task-started")
        }
    }

    /// 等待 task-finished 事件
    private func waitForTaskFinished() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.stopContinuation = continuation
        }
    }

    /// 消息接收循环
    private func receiveMessageLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // 继续接收下一条消息
                if self.state != .disconnected && self.state != .finished {
                    self.receiveMessageLoop()
                }

            case .failure(let error):
                print("[AliyunASR] WebSocket error: \(error)")
                if let continuation = self.stopContinuation {
                    continuation.resume(throwing: error)
                    self.stopContinuation = nil
                }
            }
        }
    }

    /// 处理消息
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)
        case .data(let data):
            print("[AliyunASR] Received binary data: \(data.count) bytes")
        @unknown default:
            break
        }
    }

    /// 处理文本消息
    private func handleTextMessage(_ text: String) {
        guard let jsonData = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let event = header["event"] as? String else {
            print("[AliyunASR] Invalid message format")
            return
        }

        switch event {
        case "task-started":
            handleTaskStarted()

        case "result-generated":
            handleResultGenerated(json: json)

        case "task-finished":
            handleTaskFinished()

        case "task-failed":
            let errorMessage = header["error_message"] as? String ?? "Unknown error"
            handleTaskFailed(errorMessage)

        default:
            print("[AliyunASR] Unknown event: \(event)")
        }
    }

    /// 处理 task-started
    private func handleTaskStarted() {
        taskStartedTime = Date()
        logTiming("✅ 收到 task-started")

        print("[AliyunASR] Task started")
        state = .connected
        onStateChange?(.connected)
    }

    /// 处理识别结果
    private func handleResultGenerated(json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
              let output = payload["output"] as? [String: Any],
              let sentence = output["sentence"] as? [String: Any],
              let text = sentence["text"] as? String,
              !text.isEmpty else {
            return
        }

        // 记录第一个转录结果时间
        if firstTranscriptTime == nil {
            firstTranscriptTime = Date()
            logTiming("📝 收到第一个转录结果: \(text)")
        }

        let isSentenceEnd = sentence["sentence_end"] as? Bool ?? false
        let beginTime = sentence["begin_time"] as? Int
        let endTime = sentence["end_time"] as? Int

        print("[AliyunASR] Result: \(text), isFinal: \(isSentenceEnd)")

        if isSentenceEnd {
            // 句子完成，添加到结果列表
            transcriptParts.append(text)
            currentInterimText = ""
        } else {
            // 中间结果
            currentInterimText = text
        }

        // 回调
        let result = ASRTranscriptResult(
            text: text,
            isFinal: isSentenceEnd,
            beginTime: beginTime,
            endTime: endTime
        )
        onTranscript?(result)
    }

    /// 处理 task-finished
    private func handleTaskFinished() {
        taskFinishedTime = Date()
        logTiming("🏁 收到 task-finished")

        print("[AliyunASR] Task finished")
        state = .finished
        onStateChange?(.finished)

        // 返回完整转录
        let fullTranscript = transcriptParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        stopContinuation?.resume(returning: fullTranscript)
        stopContinuation = nil
    }

    /// 处理 task-failed
    private func handleTaskFailed(_ errorMessage: String) {
        print("[AliyunASR] Task failed: \(errorMessage)")
        state = .error(errorMessage)
        onStateChange?(.error(errorMessage))

        stopContinuation?.resume(throwing: ASRClientError.serverError(errorMessage))
        stopContinuation = nil
    }
}

// MARK: - Convenience Method for Batch Processing

/// 批量转录响应
struct TranscriptionResponse {
    let success: Bool
    let text: String?
    let error: String?
}

extension AliyunASRClient {
    /// 批量转录（一次性发送所有音频）
    /// - Parameter pcmData: PCM 音频数据
    /// - Returns: 转录响应
    func transcribe(pcmData: Data) async throws -> TranscriptionResponse {
        print("[AliyunASR] Batch transcription, audio size: \(pcmData.count) bytes")

        // 开始会话
        try await start()

        // 分批发送音频（模拟实时流）
        let chunkSize = 3200 // 100ms @ 16kHz, 16-bit, mono
        var offset = 0

        while offset < pcmData.count {
            let end = min(offset + chunkSize, pcmData.count)
            let chunk = pcmData.subdata(in: offset..<end)
            sendAudio(chunk)
            offset = end

            // 小延迟，模拟实时流
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // 停止并获取结果
        let transcript = try await stop()

        let success = !transcript.isEmpty
        return TranscriptionResponse(
            success: success,
            text: success ? transcript : nil,
            error: success ? nil : "未检测到语音"
        )
    }
}
