//
//  LongRecordingService.swift
//  VoxLink
//
//  持续录音服务 - 协调音频捕获、VAD检测、实时转写和数据存储
//

import AVFoundation
import Combine
import Foundation

/// 持续录音状态
enum LongRecordingState: Equatable {
    case idle
    case recording
    case paused
    case processing  // 处理最后一段语音

    var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .recording: return "录音中"
        case .paused: return "已暂停"
        case .processing: return "处理中"
        }
    }
}

/// 持续录音服务
@MainActor
final class LongRecordingService: ObservableObject {
    // MARK: - Singleton

    static let shared = LongRecordingService()

    // MARK: - Published Properties

    @Published private(set) var state: LongRecordingState = .idle
    @Published private(set) var currentSessionId: Int64?
    @Published private(set) var recordingDuration: TimeInterval = 0  // 秒
    @Published private(set) var currentSegments: [VoiceSegment] = []

    /// 当前思维段列表（用于时间轴显示）
    @Published private(set) var currentThoughtSegments: [ThoughtSegment] = []

    /// 当前实时转录文本
    @Published private(set) var currentTranscript: String = ""

    /// 当前思维段的实时转录文本（正在进行的思维段）
    @Published private(set) var currentThoughtTranscript: String = ""

    // MARK: - Callbacks

    /// 新片段添加回调
    var onSegmentAdded: ((VoiceSegment) -> Void)?

    /// 思维段更新回调
    var onThoughtSegmentUpdate: ((ThoughtSegment) -> Void)?

    /// 思维段完成回调（静音超时后）
    var onThoughtSegmentCompleted: ((ThoughtSegment) -> Void)?

    /// 转录更新回调
    var onTranscriptUpdate: ((String) -> Void)?

    /// 录音时长更新回调
    var onDurationUpdate: ((TimeInterval) -> Void)?

    // MARK: - Private Properties

    private let audioCapture = AudioCapture()
    private let store = LongRecordingStore.shared

    private var vadProcessor: VADProcessor.RealtimeProcessor?
    private var asrClient: ASRStreamingClient?

    /// 当前会话使用的 API Key（BYOK 模式）
    private var currentSessionApiKey: String?

    private var audioLevelCancellable: AnyCancellable?
    private var pcmDataCancellable: AnyCancellable?

    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    /// 当前语音段的开始时间（相对于会话开始，毫秒）
    private var currentSegmentStartOffset: TimeInterval?

    /// 音频缓冲区（用于保存当前语音段的音频）
    private var currentSegmentAudioBuffer: Data = Data()

    /// 预缓冲区（始终保存最近 2 秒的音频，用于捕获语音开始前的内容）
    private var preBuffer: Data = Data()
    /// 预缓冲区大小：2 秒 = 16000 samples/sec * 2 bytes * 2 sec = 64000 bytes
    private let preBufferSize = 16000 * 2 * 2

    /// 预缓冲区对应的时长（毫秒）
    private var preBufferDuration: TimeInterval = 0

    /// 待发送的音频缓冲区（ASR 启动期间的音频帧）
    private var pendingAudioBuffer: Data = Data()

    /// ASR 是否就绪（可以发送音频）
    private var isASRReady: Bool = false

    /// ASR 是否正在启动中
    private var isASRStarting: Bool = false

    /// 是否正在保存语音段（用于防止竞态条件）
    private var isSavingSegment: Bool = false

    /// 当前语音段的开始时间（用于计算时长）
    private var currentSegmentStartTime: Date?

    /// 语音段时长阈值（秒）- 超过此时长且 ASR 返回句子完成时，主动保存
    private let segmentDurationThreshold: TimeInterval = 20.0

    /// 累计处理的音频时长（毫秒）
    private var totalProcessedDuration: TimeInterval = 0

    // MARK: - Thought Segment Properties

    /// 当前思维段 ID（如果有正在进行的思维段）
    private var currentThoughtSegmentId: Int64?

    /// 当前思维段的开始时间（毫秒）
    private var currentThoughtStartOffset: TimeInterval?

    /// 思维段静音计时器
    private var thoughtSegmentSilenceTimer: Timer?

    /// 上次语音活动时间（用于检测静音）
    private var lastSpeechActivityTime: Date?

    // MARK: - Initialization

    private init() {
        print("[LongRecordingService] Initialized")
    }

    // MARK: - Public Methods

    /// 开始持续录音
    func startRecording() async {
        print("[LongRecordingService] startRecording called, current state: \(state)")

        guard state == .idle else {
            print("[LongRecordingService] Already recording or paused")
            return
        }

        // 检查 VAD 是否已初始化
        print("[LongRecordingService] Checking VAD initialization...")
        if !VADService.shared.isInitialized {
            print("[LongRecordingService] VAD not initialized, initializing...")
            do {
                _ = try await VADService.shared.initialize()
            } catch {
                print("[LongRecordingService] VAD initialization error: \(error)")
            }

            if !VADService.shared.isInitialized {
                print("[LongRecordingService] Failed to initialize VAD")
                return
            }
        }
        print("[LongRecordingService] VAD is ready")

        // 1. 确定使用的凭证（BYOK 模式）
        currentSessionApiKey = nil

        guard let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty else {
            print("[LongRecordingService] No API Key configured")
            return
        }
        // BYOK 模式：直连阿里云
        print("[LongRecordingService] Using BYOK mode with custom Aliyun API Key")
        currentSessionApiKey = key

        // 创建新会话
        print("[LongRecordingService] Creating session...")
        guard let session = store.createSession() else {
            print("[LongRecordingService] Failed to create session")
            return
        }
        print("[LongRecordingService] Session created: \(session.id)")

        currentSessionId = session.id
        recordingStartTime = Date()
        recordingDuration = 0
        currentSegments = []
        currentThoughtSegments = []
        currentTranscript = ""
        currentThoughtTranscript = ""
        totalProcessedDuration = 0
        currentSegmentStartOffset = nil
        currentSegmentAudioBuffer = Data()
        preBuffer = Data()
        preBufferDuration = 0
        pendingAudioBuffer = Data()
        isASRReady = false
        isASRStarting = false
        isSavingSegment = false
        currentSegmentStartTime = nil

        // 初始化思维段状态
        currentThoughtSegmentId = nil
        currentThoughtStartOffset = nil
        lastSpeechActivityTime = nil
        stopThoughtSegmentSilenceTimer()

        do {
            // 初始化 VAD 实时处理器（使用更长的静音填充时长，避免说话中的短暂停顿导致分段）
            // 持续录音模式下，使用 3.5 秒的静音填充，比普通录音的 1.5 秒更长
            let vadConfig = VADConfig(
                speechThreshold: 0.5,
                silencePadding: 3.5,  // 持续录音模式使用更长的静音填充
                minSpeechDuration: 0.3
            )
            vadProcessor = try VADService.shared.createRealtimeProcessor(customConfig: vadConfig)
            print("[LongRecordingService] VAD processor created with silencePadding: \(vadConfig.silencePadding)s")

            // 语音开始时启动 ASR
            vadProcessor?.onSpeechStarted = { [weak self] startTime in
                Task { @MainActor in
                    self?.handleSpeechStarted(at: startTime)
                }
            }

            // 语音结束时停止 ASR 并保存片段
            vadProcessor?.onSpeechSegmentDetected = { [weak self] segment in
                Task { @MainActor in
                    self?.handleSpeechSegmentEnded(segment)
                }
            }

            // 初始化 ASR 客户端（延迟到语音开始时才启动）
            // 凭证逻辑已在上面的凭证判断中处理
            // ASR 客户端将在 handleSpeechStarted 中根据需要创建

            asrClient?.onTranscript = { [weak self] result in
                Task { @MainActor in
                    self?.handleTranscriptUpdate(result)
                }
            }

            // 启动音频捕获
            try audioCapture.startCapture(accumulateBuffer: false)

            // 订阅音频数据流
            pcmDataCancellable = audioCapture.pcmDataPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] pcmData in
                    self?.processAudioData(pcmData)
                }

            // 启动时长计时器
            startDurationTimer()

            state = .recording
            print("[LongRecordingService] Started recording, session: \(session.id)")

        } catch {
            print("[LongRecordingService] Failed to start recording: \(error)")
            // 清理
            if let sessionId = currentSessionId {
                store.deleteSession(sessionId)
            }
            currentSessionId = nil
            state = .idle
        }
    }

    /// 暂停录音
    func pauseRecording() async {
        guard state == .recording else { return }

        print("[LongRecordingService] pauseRecording called")

        // 保存当前正在进行的语音段
        await finalizeCurrentSegment()

        // 停止 ASR
        _ = try? await asrClient?.stop()
        asrClient = nil

        // 停止音频捕获
        _ = audioCapture.stopCapture()
        pcmDataCancellable?.cancel()
        pcmDataCancellable = nil

        // 停止时长计时器
        stopDurationTimer()

        // 更新状态
        state = .paused
        store.updateSessionStatus(currentSessionId!, status: .paused)

        print("[LongRecordingService] Paused recording")
    }

    /// 恢复录音
    func resumeRecording() async {
        guard state == .paused else { return }

        let settings = SettingsStore.shared

        do {
            // 重新初始化 ASR 客户端（BYOK 模式）
            guard let key = currentSessionApiKey else {
                print("[LongRecordingService] No API Key for resume")
                return
            }
            let mode: AliyunASRMode = settings.aliyunRegion == "singapore" ? .singapore : .server
            asrClient = AliyunASRClient(apiKey: key, mode: mode)

            asrClient?.onTranscript = { [weak self] result in
                Task { @MainActor in
                    self?.handleTranscriptUpdate(result)
                }
            }

            // 重置 VAD 处理器和 ASR 状态
            vadProcessor?.reset()
            isASRReady = false
            isASRStarting = false
            pendingAudioBuffer = Data()

            // 继续音频捕获
            try audioCapture.startCapture(accumulateBuffer: false)

            // 重新订阅音频数据
            pcmDataCancellable = audioCapture.pcmDataPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] pcmData in
                    self?.processAudioData(pcmData)
                }

            // 重新启动时长计时器
            startDurationTimer()

            state = .recording
            store.updateSessionStatus(currentSessionId!, status: .recording)

            print("[LongRecordingService] Resumed recording")

        } catch {
            print("[LongRecordingService] Failed to resume recording: \(error)")
        }
    }

    /// 停止录音
    func stopRecording() async {
        guard state == .recording || state == .paused else { return }

        print("[LongRecordingService] stopRecording called")
        state = .processing

        // 保存当前正在进行的语音段
        await finalizeCurrentSegment()

        // 完成当前思维段
        await finalizeCurrentThoughtSegmentForStop()

        // 停止 ASR
        _ = try? await asrClient?.stop()
        asrClient = nil

        // 停止音频捕获
        _ = audioCapture.stopCapture()
        pcmDataCancellable?.cancel()
        pcmDataCancellable = nil

        // 停止时长计时器
        stopDurationTimer()

        // 停止思维段静音计时器
        stopThoughtSegmentSilenceTimer()

        // 完成会话
        if let sessionId = currentSessionId {
            store.completeSession(sessionId)
        }

        // 重置所有状态
        currentSessionId = nil
        recordingDuration = 0
        currentTranscript = ""
        currentThoughtTranscript = ""
        currentSegments = []
        currentThoughtSegments = []
        totalProcessedDuration = 0
        currentSegmentStartOffset = nil
        currentSegmentAudioBuffer = Data()
        preBuffer = Data()
        preBufferDuration = 0
        pendingAudioBuffer = Data()
        isASRReady = false
        isASRStarting = false
        currentThoughtSegmentId = nil
        currentThoughtStartOffset = nil
        lastSpeechActivityTime = nil
        state = .idle

        print("[LongRecordingService] Stopped recording")
    }

    /// 取消录音
    func cancelRecording() {
        guard state == .recording || state == .paused else { return }

        // 停止音频捕获
        _ = audioCapture.stopCapture()
        pcmDataCancellable?.cancel()
        pcmDataCancellable = nil

        // 停止时长计时器
        stopDurationTimer()

        // 停止思维段静音计时器
        stopThoughtSegmentSilenceTimer()

        // 删除会话
        if let sessionId = currentSessionId {
            store.deleteSession(sessionId)
        }

        // 重置所有状态
        currentSessionId = nil
        recordingDuration = 0
        currentTranscript = ""
        currentThoughtTranscript = ""
        currentSegments = []
        currentThoughtSegments = []
        totalProcessedDuration = 0
        currentSegmentStartOffset = nil
        currentSegmentAudioBuffer = Data()
        preBuffer = Data()
        preBufferDuration = 0
        pendingAudioBuffer = Data()
        isASRReady = false
        isASRStarting = false
        currentThoughtSegmentId = nil
        currentThoughtStartOffset = nil
        lastSpeechActivityTime = nil
        state = .idle

        print("[LongRecordingService] Cancelled recording")
    }

    // MARK: - Private Methods

    /// 处理音频数据
    private func processAudioData(_ pcmData: Data) {
        guard state == .recording else { return }

        // 将 Data 转换为 Int16 数组
        let frameSize = 512
        let sampleCount = pcmData.count / 2

        pcmData.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let samples = baseAddress.assumingMemoryBound(to: Int16.self)

            // 按帧处理
            var offset = 0
            while offset + frameSize <= sampleCount {
                let frame = Array(UnsafeBufferPointer(start: samples.advanced(by: offset), count: frameSize))
                let frameData = Data(bytes: samples.advanced(by: offset), count: frameSize * 2)

                // 始终将音频添加到预缓冲区（用于捕获语音开始前的内容）
                preBuffer.append(frameData)
                preBufferDuration += 32  // 每帧 32ms
                // 保持预缓冲区大小限制
                if preBuffer.count > preBufferSize {
                    let excess = preBuffer.count - preBufferSize
                    preBuffer.removeFirst(excess)
                    preBufferDuration = TimeInterval(preBuffer.count / 2) / 16.0  // 重新计算时长（毫秒）
                }

                // 发送给 VAD 处理
                vadProcessor?.processFrame(frame)

                // 如果正在语音段中，保存音频数据并发送给 ASR
                if vadProcessor?.isInSpeech == true {
                    currentSegmentAudioBuffer.append(frameData)

                    // 如果 ASR 已就绪，直接发送；否则缓冲起来
                    if isASRReady {
                        asrClient?.sendAudio(frameData)
                    } else {
                        pendingAudioBuffer.append(frameData)
                        // 限制缓冲区大小（最多 500ms 音频）
                        let maxBufferSize = 16000 * 2 / 2  // 16000 samples/sec * 2 bytes * 0.5 sec
                        if pendingAudioBuffer.count > maxBufferSize {
                            let excess = pendingAudioBuffer.count - maxBufferSize
                            pendingAudioBuffer.removeFirst(excess)
                        }
                    }
                }

                offset += frameSize
            }
        }
    }

    /// 处理语音开始事件
    private func handleSpeechStarted(at startTime: Double) {
        guard state == .recording else { return }

        // 等待上一个语音段保存完成（防止竞态条件）
        Task {
            var waitCount = 0
            while isSavingSegment && waitCount < 100 {  // 最多等待 10 秒
                print("[LongRecordingService] Waiting for previous segment to save...")
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                waitCount += 1
            }
            if isSavingSegment {
                print("[LongRecordingService] Warning: Previous segment save timed out, proceeding anyway")
            }

            // 在主线程上执行后续操作
            await MainActor.run {
                self.doHandleSpeechStarted(at: startTime)
            }
        }
    }

    /// 实际处理语音开始事件（在确保上一个段保存完成后调用）
    private func doHandleSpeechStarted(at startTime: Double) {
        guard state == .recording else { return }

        // 重要：取消思维段静音计时器，因为用户又开始说话了
        // 这样可以确保新的语音段会追加到当前思维段，而不是创建新的思维段
        stopThoughtSegmentSilenceTimer()

        // 计算实际语音开始时间（考虑预缓冲区）
        // 预缓冲区保存了最近 2 秒的音频，所以实际开始时间更早
        let adjustedStartTime = max(0, startTime * 1000 - preBufferDuration)
        currentSegmentStartOffset = adjustedStartTime
        currentSegmentStartTime = Date()  // 记录语音段开始时间
        currentTranscript = ""
        currentSegmentAudioBuffer = Data()

        // 将预缓冲区的音频作为待发送音频的开始部分
        pendingAudioBuffer = preBuffer
        print("[LongRecordingService] Speech started at \(startTime)s, adjusted to \(adjustedStartTime)ms (preBuffer: \(preBufferDuration)ms, \(preBuffer.count) bytes)")

        isASRReady = false
        isASRStarting = true

        // 启动 ASR 实时转写
        Task {
            do {
                // BYOK 模式：创建 ASR 客户端
                if asrClient == nil {
                    guard let key = currentSessionApiKey else {
                        print("[LongRecordingService] No API Key for ASR")
                        isASRStarting = false
                        return
                    }
                    // BYOK 模式：直连阿里云
                    let mode: AliyunASRMode = SettingsStore.shared.aliyunRegion == "singapore" ? .singapore : .server
                    asrClient = AliyunASRClient(apiKey: key, mode: mode)
                    print("[LongRecordingService] Created AliyunASRClient for BYOK mode")

                    asrClient?.onTranscript = { [weak self] result in
                        Task { @MainActor in
                            self?.handleTranscriptUpdate(result)
                        }
                    }
                }

                try await asrClient?.start()
                print("[LongRecordingService] ASR started for speech at \(startTime)s")

                // ASR 已就绪，发送缓冲的音频（包含预缓冲区）
                isASRReady = true
                isASRStarting = false
                if !pendingAudioBuffer.isEmpty {
                    asrClient?.sendAudio(pendingAudioBuffer)
                    print("[LongRecordingService] Sent \(pendingAudioBuffer.count) bytes buffered audio (including preBuffer)")
                    pendingAudioBuffer = Data()
                }
            } catch {
                print("[LongRecordingService] Failed to start ASR: \(error)")
                isASRStarting = false
                isASRReady = false
                // 清理当前段状态，避免后续保存空片段
                currentSegmentStartOffset = nil
                currentSegmentStartTime = nil
                currentTranscript = ""
                currentSegmentAudioBuffer = Data()
                pendingAudioBuffer = Data()
            }
        }
    }

    /// 处理语音段结束事件
    private func handleSpeechSegmentEnded(_ segment: SpeechSegment) {
        guard state == .recording else { return }

        // 更新处理时长
        totalProcessedDuration = segment.endTime * 1000

        // 保存当前片段
        Task {
            await self.saveCurrentSegment(endTime: segment.endTime)
        }
    }

    /// 保存当前语音段
    private func saveCurrentSegment(endTime: Double) async {
        guard let sessionId = currentSessionId,
              let startOffset = currentSegmentStartOffset else { return }

        // 如果已经在保存中，跳过（防止重复保存）
        if isSavingSegment {
            print("[LongRecordingService] Already saving segment, skipping")
            return
        }

        // 标记正在保存
        isSavingSegment = true

        // 等待 ASR 启动完成（如果正在启动中）
        var waitCount = 0
        while isASRStarting && waitCount < 50 {  // 最多等待 5 秒
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            waitCount += 1
        }

        // 标记 ASR 不再就绪
        isASRReady = false
        isASRStarting = false

        // 停止 ASR 并获取最终转录
        let transcript = (try? await asrClient?.stop()) ?? currentTranscript

        // 计算结束时间
        let endOffset = endTime * 1000

        // 保存语音片段（保留原有逻辑）
        if !transcript.isEmpty {
            let segment = store.addSegment(
                sessionId: sessionId,
                startOffset: startOffset,
                endOffset: endOffset,
                transcript: transcript
            )

            if let segment = segment {
                currentSegments.append(segment)
                onSegmentAdded?(segment)
                print("[LongRecordingService] Saved segment: \(transcript.prefix(50))...")

                // 更新思维段
                await updateThoughtSegment(with: transcript, startOffset: startOffset, endOffset: endOffset)
            }
        } else {
            print("[LongRecordingService] Skipping empty segment")
            // 如果有正在进行的思维段，启动静音计时器
            // 这样当用户停止说话后，即使遇到空片段也能触发润色
            if currentThoughtSegmentId != nil {
                print("[LongRecordingService] Starting silence timer for active thought segment after empty segment")
                startThoughtSegmentSilenceTimer()
            }
        }

        // 重置当前段状态
        currentSegmentStartOffset = nil
        currentSegmentStartTime = nil
        currentTranscript = ""
        currentSegmentAudioBuffer = Data()
        pendingAudioBuffer = Data()

        // 保存完成
        isSavingSegment = false
    }

    /// 更新思维段（聚合语音片段）
    /// - Parameters:
    ///   - transcript: 转录文本
    ///   - startOffset: 开始时间偏移
    ///   - endOffset: 结束时间偏移
    ///   - restartSilenceTimer: 是否重启静音计时器（基于时长保存时为 false，避免思维段被错误分割）
    private func updateThoughtSegment(with transcript: String, startOffset: TimeInterval, endOffset: TimeInterval, restartSilenceTimer: Bool = true) async {
        guard let sessionId = currentSessionId else { return }

        // 更新语音活动时间
        lastSpeechActivityTime = Date()

        // 如果没有当前思维段，创建一个新的
        if currentThoughtSegmentId == nil {
            let position = store.getNextThoughtSegmentPosition(for: sessionId)
            let thoughtSegment = store.addThoughtSegment(
                sessionId: sessionId,
                startOffset: startOffset,
                endOffset: endOffset,
                rawTranscript: transcript,
                position: position
            )

            if let thoughtSegment = thoughtSegment {
                currentThoughtSegmentId = thoughtSegment.id
                currentThoughtStartOffset = startOffset
                currentThoughtTranscript = transcript
                currentThoughtSegments.append(thoughtSegment)
                onThoughtSegmentUpdate?(thoughtSegment)
                print("[LongRecordingService] Created thought segment \(thoughtSegment.id) at position \(position)")
            }
        } else {
            // 追加到现有思维段
            store.appendThoughtSegmentRaw(currentThoughtSegmentId!, additionalTranscript: transcript, newEndOffset: endOffset)

            // 更新当前思维段转录文本
            currentThoughtTranscript = currentThoughtTranscript.isEmpty ? transcript : currentThoughtTranscript + " " + transcript

            // 更新本地列表中的思维段（必须更新 rawTranscript，否则润色时会用旧值）
            if let index = currentThoughtSegments.firstIndex(where: { $0.id == currentThoughtSegmentId }) {
                let oldSegment = currentThoughtSegments[index]
                // 创建新的 ThoughtSegment 并更新 rawTranscript
                currentThoughtSegments[index] = ThoughtSegment(
                    id: oldSegment.id,
                    sessionId: oldSegment.sessionId,
                    startOffset: oldSegment.startOffset,
                    endOffset: endOffset,
                    rawTranscript: currentThoughtTranscript,  // 使用更新后的完整转录
                    polishedTranscript: oldSegment.polishedTranscript,
                    isPolished: oldSegment.isPolished,
                    position: oldSegment.position,
                    createdAt: oldSegment.createdAt,
                    polishedAt: oldSegment.polishedAt
                )
                onThoughtSegmentUpdate?(currentThoughtSegments[index])
            }

            print("[LongRecordingService] Appended to thought segment \(currentThoughtSegmentId!)")
        }

        // 只有在需要时才启动/重启静音计时器
        // 基于时长保存时不重启，避免思维段被错误分割
        if restartSilenceTimer {
            startThoughtSegmentSilenceTimer()
        }
    }

    /// 启动思维段静音计时器
    private func startThoughtSegmentSilenceTimer() {
        // 先停止现有计时器
        stopThoughtSegmentSilenceTimer()

        let silenceSeconds = Double(SettingsStore.shared.thoughtSegmentSilenceSeconds)
        print("[LongRecordingService] ⬇️ ====== 思维段静音阈值: \(silenceSeconds) 秒 ======")
        print("[LongRecordingService] Starting thought segment silence timer: \(silenceSeconds)s")

        thoughtSegmentSilenceTimer = Timer.scheduledTimer(withTimeInterval: silenceSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.finalizeCurrentThoughtSegment()
            }
        }
    }

    /// 停止思维段静音计时器
    private func stopThoughtSegmentSilenceTimer() {
        thoughtSegmentSilenceTimer?.invalidate()
        thoughtSegmentSilenceTimer = nil
    }

    /// 完成当前思维段（静音超时后调用）
    private func finalizeCurrentThoughtSegment() async {
        guard let thoughtSegmentId = currentThoughtSegmentId else {
            print("[LongRecordingService] No current thought segment to finalize")
            return
        }

        // 如果 ASR 正在重启中（基于时长的保存），不关闭思维段
        // 因为用户可能还在说话，只是我们在切换 ASR 会话
        if isASRStarting || isSavingSegment {
            print("[LongRecordingService] ASR is restarting or saving, postponing thought segment finalization")
            // 重新启动计时器，稍后再试
            startThoughtSegmentSilenceTimer()
            return
        }

        print("[LongRecordingService] Finalizing thought segment \(thoughtSegmentId)")

        // AI 润色始终启用
        if true {
            // 调用 AI 润色服务
            await polishThoughtSegment(thoughtSegmentId)
        }

        // 通知思维段完成
        if let index = currentThoughtSegments.firstIndex(where: { $0.id == thoughtSegmentId }) {
            onThoughtSegmentCompleted?(currentThoughtSegments[index])
        }

        // 重置当前思维段状态
        currentThoughtSegmentId = nil
        currentThoughtStartOffset = nil
        currentThoughtTranscript = ""
    }

    /// 对思维段进行 AI 润色
    private func polishThoughtSegment(_ segmentId: Int64) async {
        guard let segment = currentThoughtSegments.first(where: { $0.id == segmentId }) else {
            print("[LongRecordingService] Thought segment \(segmentId) not found for polishing")
            return
        }

        let rawText = segment.rawTranscript
        guard !rawText.isEmpty else {
            print("[LongRecordingService] Empty transcript, skipping polish")
            return
        }

        print("[LongRecordingService] Polishing thought segment \(segmentId)...")

        // 调用 AI 润色服务
        if let polishedText = await AIPolishService.shared.polish(rawText) {
            store.updateThoughtSegmentPolished(segmentId, polishedTranscript: polishedText)
            print("[LongRecordingService] Polished thought segment \(segmentId)")
        } else {
            print("[LongRecordingService] Failed to polish thought segment \(segmentId)")
        }
    }

    /// 完成当前语音段（用于暂停/停止时）
    private func finalizeCurrentSegment() async {
        guard currentSegmentStartOffset != nil else {
            // 没有正在进行的语音段
            return
        }

        // 使用当前处理时长作为结束时间
        let endTime = totalProcessedDuration / 1000.0
        await saveCurrentSegment(endTime: endTime)
    }

    /// 完成当前思维段（用于停止录音时）
    private func finalizeCurrentThoughtSegmentForStop() async {
        // 停止静音计时器
        stopThoughtSegmentSilenceTimer()

        // 如果有正在进行的思维段，立即完成
        if currentThoughtSegmentId != nil {
            await finalizeCurrentThoughtSegment()
        }
    }

    /// 处理转录更新
    private func handleTranscriptUpdate(_ result: ASRTranscriptResult) {
        // 使用累积的完整转录
        if let client = asrClient {
            currentTranscript = client.currentFullTranscript
            onTranscriptUpdate?(currentTranscript)
        }

        // 当 ASR 返回句子完成（isFinal: true）且语音段时长超过阈值时，主动保存
        if result.isFinal {
            checkAndSaveSegmentByDuration()
        }
    }

    /// 检查是否需要基于时长保存语音段
    private func checkAndSaveSegmentByDuration() {
        // 检查条件：正在录音、有语音段开始时间、不在保存中
        guard state == .recording,
              let segmentStartTime = currentSegmentStartTime,
              !isSavingSegment else {
            return
        }

        let segmentDuration = Date().timeIntervalSince(segmentStartTime)

        // 如果语音段时长超过阈值，主动保存
        if segmentDuration >= segmentDurationThreshold {
            print("[LongRecordingService] Segment duration \(String(format: "%.1f", segmentDuration))s >= threshold \(segmentDurationThreshold)s, triggering save")

            // 异步保存当前语音段，但不停止 ASR，而是启动新的 ASR 会话
            Task {
                await self.saveSegmentAndContinueASR()
            }
        }
    }

    /// 保存语音段并继续 ASR（用于基于时长的保存）
    private func saveSegmentAndContinueASR() async {
        guard let sessionId = currentSessionId,
              let startOffset = currentSegmentStartOffset,
              !isSavingSegment else { return }

        // 标记正在保存
        isSavingSegment = true

        // 等待 ASR 启动完成（如果正在启动中）
        var waitCount = 0
        while isASRStarting && waitCount < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waitCount += 1
        }

        // 标记 ASR 不再就绪
        isASRReady = false
        isASRStarting = false

        // 停止当前 ASR 并获取转录
        let transcript = (try? await asrClient?.stop()) ?? currentTranscript

        // 计算结束时间
        let endOffset = totalProcessedDuration

        // 保存语音片段
        if !transcript.isEmpty {
            let segment = store.addSegment(
                sessionId: sessionId,
                startOffset: startOffset,
                endOffset: endOffset,
                transcript: transcript
            )

            if let segment = segment {
                currentSegments.append(segment)
                onSegmentAdded?(segment)
                print("[LongRecordingService] Saved segment by duration: \(transcript.prefix(50))...")

                // 更新思维段，但不重启静音计时器（避免思维段被错误分割）
                await updateThoughtSegment(with: transcript, startOffset: startOffset, endOffset: endOffset, restartSilenceTimer: false)
            }
        } else {
            print("[LongRecordingService] Skipping empty segment (duration-based)")
        }

        // 重置当前语音段状态，准备开始新段
        currentSegmentStartOffset = endOffset
        currentSegmentStartTime = Date()
        currentTranscript = ""
        currentSegmentAudioBuffer = Data()
        pendingAudioBuffer = preBuffer  // 保留预缓冲区

        // 重新启动 ASR（继续发送音频）
        isASRStarting = true

        do {
            try await asrClient?.start()
            print("[LongRecordingService] ASR restarted for continued speech")
            isASRReady = true
            isASRStarting = false

            // 发送预缓冲区音频
            if !pendingAudioBuffer.isEmpty {
                asrClient?.sendAudio(pendingAudioBuffer)
                pendingAudioBuffer = Data()
            }
        } catch {
            print("[LongRecordingService] Failed to restart ASR: \(error)")
            isASRStarting = false
            isASRReady = false
        }

        // 保存完成
        isSavingSegment = false
    }

    /// 启动时长计时器
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
                self.onDurationUpdate?(self.recordingDuration)
            }
        }
    }

    /// 停止时长计时器
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Audio Level

    /// 音量级别发布者
    var audioLevelPublisher: AnyPublisher<CGFloat, Never> {
        audioCapture.audioLevelPublisher
    }
}
