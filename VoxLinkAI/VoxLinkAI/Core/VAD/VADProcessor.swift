//
//  VADProcessor.swift
//  VoxLink
//
//  VAD 处理管道 - 音频分帧、语音检测、片段提取
//
//  处理流程：
//  1. 接收 16kHz 单声道 PCM 音频数据
//  2. 分帧处理（每帧 512 采样点 = 32ms）
//  3. 使用 Silero VAD 检测每帧是否包含语音
//  4. 合并连续的语音帧为人声片段
//  5. 输出人声片段的时间戳
//

import Foundation

// MARK: - Types

/// 语音片段
public struct SpeechSegment {
    /// 开始时间（秒）
    public let startTime: Double
    /// 结束时间（秒）
    public let endTime: Double
    /// 持续时间（秒）
    public var duration: Double {
        endTime - startTime
    }
    /// 音频数据（可选，用于后续 ASR 处理）
    public var audioData: Data?

    public init(startTime: Double, endTime: Double, audioData: Data? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.audioData = audioData
    }
}

/// VAD 处理器配置
public struct VADConfig {
    /// 语音检测阈值（0.0 - 1.0）
    public var speechThreshold: Float = 0.5

    /// 静音填充时长（秒）- 短于此时长的静音不会断开语音片段
    /// 用于避免说话中的短暂停顿导致片段分裂
    /// 建议 1.0-2.0 秒，避免过于频繁的分段
    public var silencePadding: Double = 1.5

    /// 最小语音片段时长（秒）- 短于此时长的片段将被过滤
    public var minSpeechDuration: Double = 0.3

    /// 采样率
    public let sampleRate: Int = 16000

    /// 帧大小（采样点数）
    public let frameSize: Int = 512

    /// 帧时长（秒）
    public var frameDuration: Double {
        Double(frameSize) / Double(sampleRate)
    }

    public init(
        speechThreshold: Float = 0.5,
        silencePadding: Double = 1.5,
        minSpeechDuration: Double = 0.3
    ) {
        self.speechThreshold = speechThreshold
        self.silencePadding = silencePadding
        self.minSpeechDuration = minSpeechDuration
    }
}

/// VAD 处理器状态
public enum VADProcessorState {
    case idle
    case processing
    case paused
}

/// VAD 处理结果
public struct VADProcessResult {
    /// 检测到的语音片段
    public let segments: [SpeechSegment]
    /// 总处理时长（秒）
    public let totalDuration: Double
    /// 语音总时长（秒）
    public let speechDuration: Double
    /// 语音占比
    public var speechRatio: Double {
        guard totalDuration > 0 else { return 0 }
        return speechDuration / totalDuration
    }
}

// MARK: - VADProcessor

/// VAD 处理器
///
/// 处理音频数据并提取语音片段。
///
/// 使用示例：
/// ```swift
/// let processor = try VADProcessor(modelPath: "silero_vad.onnx")
/// let result = try processor.process(audioData: pcmData)
/// for segment in result.segments {
///     print("语音: \(segment.startTime)s - \(segment.endTime)s")
/// }
/// ```
public final class VADProcessor {

    // MARK: - Properties

    private let vad: SileroVAD
    private let config: VADConfig
    private(set) public var state: VADProcessorState = .idle

    /// 处理队列
    private let processingQueue = DispatchQueue(label: "com.voxlinkai.vad", qos: .userInitiated)

    // MARK: - Initialization

    /// 初始化 VAD 处理器
    /// - Parameters:
    ///   - modelPath: Silero VAD 模型路径
    ///   - config: 处理器配置
    public init(modelPath: String, config: VADConfig = VADConfig()) throws {
        self.vad = try SileroVAD(modelPath: modelPath, threshold: config.speechThreshold)
        self.config = config
        print("[VADProcessor] Initialized with config: threshold=\(config.speechThreshold), silencePadding=\(config.silencePadding)s")
    }

    /// 从 Bundle 资源初始化
    public convenience init(bundle: Bundle = .main, config: VADConfig = VADConfig()) throws {
        guard let modelPath = bundle.path(forResource: "silero_vad", ofType: "onnx") else {
            throw SileroVADError.modelNotFound
        }
        try self.init(modelPath: modelPath, config: config)
    }

    // MARK: - Processing

    /// 处理音频数据并提取语音片段
    /// - Parameter audioData: PCM 音频数据（16kHz, mono, 16-bit signed）
    /// - Returns: 处理结果，包含所有语音片段
    public func process(audioData: Data) throws -> VADProcessResult {
        state = .processing
        defer { state = .idle }

        // 重置 VAD 状态
        vad.resetState()

        // 将 Data 转换为 Int16 数组
        let int16Count = audioData.count / 2
        let int16Data = audioData.withUnsafeBytes { ptr in
            Array(ptr.bindMemory(to: Int16.self))
        }

        // 计算总帧数
        let frameCount = int16Count / config.frameSize
        let totalDuration = Double(int16Count) / Double(config.sampleRate)

        print("[VADProcessor] Processing \(totalDuration)s audio, \(frameCount) frames")

        // 检测每帧
        var frameResults: [(isSpeech: Bool, probability: Float)] = []

        for frameIndex in 0..<frameCount {
            let offset = frameIndex * config.frameSize
            let frameEnd = min(offset + config.frameSize, int16Count)
            let frame = Array(int16Data[offset..<frameEnd])

            // 如果最后一帧不完整，填充零
            var paddedFrame = frame
            if frame.count < config.frameSize {
                paddedFrame.append(contentsOf: [Int16](repeating: 0, count: config.frameSize - frame.count))
            }

            do {
                let result = try vad.detect(int16Frame: paddedFrame)
                frameResults.append((result.isSpeech, result.probability))
            } catch {
                print("[VADProcessor] Frame \(frameIndex) detection failed: \(error)")
                frameResults.append((false, 0))
            }
        }

        // 提取语音片段
        let segments = extractSegments(from: frameResults, audioData: audioData)

        // 计算语音总时长
        let speechDuration = segments.reduce(0) { $0 + $1.duration }

        print("[VADProcessor] Found \(segments.count) segments, speech duration: \(speechDuration)s (\(String(format: "%.1f", speechDuration / totalDuration * 100))%)")

        return VADProcessResult(
            segments: segments,
            totalDuration: totalDuration,
            speechDuration: speechDuration
        )
    }

    /// 异步处理音频数据
    public func processAsync(audioData: Data, completion: @escaping (Result<VADProcessResult, Error>) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let result = try self.process(audioData: audioData)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Segment Extraction

    /// 从帧检测结果提取语音片段
    private func extractSegments(
        from frameResults: [(isSpeech: Bool, probability: Float)],
        audioData: Data
    ) -> [SpeechSegment] {
        guard !frameResults.isEmpty else { return [] }

        let frameDuration = config.frameDuration
        let silencePaddingFrames = Int(config.silencePadding / frameDuration)
        let minSpeechFrames = Int(config.minSpeechDuration / frameDuration)

        var segments: [SpeechSegment] = []
        var segmentStart: Int?
        var silenceCount = 0

        for (index, result) in frameResults.enumerated() {
            if result.isSpeech {
                // 语音帧
                if segmentStart == nil {
                    // 开始新的语音片段
                    segmentStart = index
                    silenceCount = 0
                } else {
                    // 重置静音计数
                    silenceCount = 0
                }
            } else {
                // 静音帧
                if segmentStart != nil {
                    silenceCount += 1
                    if silenceCount > silencePaddingFrames {
                        // 静音超过阈值，结束当前片段
                        let endIndex = index - silenceCount + silencePaddingFrames
                        let startTime = Double(segmentStart!) * frameDuration
                        let endTime = Double(endIndex) * frameDuration

                        // 只保留足够长的片段
                        if endIndex - segmentStart! >= minSpeechFrames {
                            let segmentAudio = extractAudioSegment(
                                from: audioData,
                                startFrame: segmentStart!,
                                endFrame: endIndex
                            )
                            segments.append(SpeechSegment(
                                startTime: startTime,
                                endTime: endTime,
                                audioData: segmentAudio
                            ))
                        }

                        segmentStart = nil
                        silenceCount = 0
                    }
                }
            }
        }

        // 处理最后一个片段
        if let start = segmentStart {
            let endTime = Double(frameResults.count) * frameDuration
            let startIndex = Double(start) * frameDuration

            if Double(frameResults.count - start) * frameDuration >= config.minSpeechDuration {
                let segmentAudio = extractAudioSegment(
                    from: audioData,
                    startFrame: start,
                    endFrame: frameResults.count
                )
                segments.append(SpeechSegment(
                    startTime: startIndex,
                    endTime: endTime,
                    audioData: segmentAudio
                ))
            }
        }

        return segments
    }

    /// 提取语音片段的音频数据
    private func extractAudioSegment(
        from audioData: Data,
        startFrame: Int,
        endFrame: Int
    ) -> Data {
        let byteOffset = startFrame * config.frameSize * 2  // 2 bytes per sample
        let byteLength = (endFrame - startFrame) * config.frameSize * 2

        guard byteOffset + byteLength <= audioData.count else {
            return Data()
        }

        return audioData.subdata(in: byteOffset..<byteOffset + byteLength)
    }

    // MARK: - Utility

    /// 重置处理器状态
    public func reset() {
        vad.resetState()
        state = .idle
    }
}

// MARK: - Real-time Processing Support

extension VADProcessor {

    /// 实时 VAD 处理器（流式处理）
    public final class RealtimeProcessor {
        private let vad: SileroVAD
        private let config: VADConfig

        private var currentSegmentStart: Double?
        private var silenceDuration: Double = 0
        private var totalProcessedDuration: Double = 0

        /// 当前是否在语音片段中
        public private(set) var isInSpeech: Bool = false

        /// 检测到语音开始的回调
        public var onSpeechStarted: ((Double) -> Void)?

        /// 检测到语音片段结束的回调
        public var onSpeechSegmentDetected: ((SpeechSegment) -> Void)?

        /// 初始化
        public init(vad: SileroVAD, config: VADConfig = VADConfig()) {
            self.vad = vad
            self.config = config
        }

        /// 处理单帧音频
        /// - Parameter frame: 音频帧（512 个 Int16 采样点）
        public func processFrame(_ frame: [Int16]) {
            do {
                let result = try vad.detect(int16Frame: frame)
                let frameDuration = config.frameDuration

                if result.isSpeech {
                    if !isInSpeech {
                        // 开始新的语音片段
                        isInSpeech = true
                        currentSegmentStart = totalProcessedDuration
                        onSpeechStarted?(totalProcessedDuration)
                    }
                    silenceDuration = 0
                } else {
                    if isInSpeech {
                        silenceDuration += frameDuration
                        if silenceDuration >= config.silencePadding {
                            // 结束当前片段
                            if let start = currentSegmentStart {
                                let end = totalProcessedDuration + frameDuration - silenceDuration
                                if end - start >= config.minSpeechDuration {
                                    let segment = SpeechSegment(startTime: start, endTime: end)
                                    onSpeechSegmentDetected?(segment)
                                }
                            }
                            isInSpeech = false
                            currentSegmentStart = nil
                        }
                    }
                }

                totalProcessedDuration += frameDuration
            } catch {
                print("[RealtimeProcessor] Frame processing error: \(error)")
            }
        }

        /// 重置状态
        public func reset() {
            vad.resetState()
            currentSegmentStart = nil
            silenceDuration = 0
            totalProcessedDuration = 0
            isInSpeech = false
        }
    }

    /// 创建实时处理器
    public func createRealtimeProcessor() -> RealtimeProcessor {
        return RealtimeProcessor(vad: vad, config: config)
    }

    /// 创建实时处理器（使用自定义配置）
    /// - Parameter customConfig: 自定义 VAD 配置
    /// - Returns: 实时处理器实例
    public func createRealtimeProcessor(customConfig: VADConfig) -> RealtimeProcessor {
        return RealtimeProcessor(vad: vad, config: customConfig)
    }
}
