//
//  SileroVAD.swift
//  VoxLink
//
//  Silero VAD 模型封装 - 使用 ONNX Runtime
//
//  使用前需要添加 ONNX Runtime Swift 依赖：
//  1. 在 Xcode 中: File > Add Packages...
//  2. 输入: https://github.com/microsoft/onnxruntime-swift-package-manager
//  3. 选择版本: 1.16.0 或更高
//  4. 将 silero_vad.onnx 模型添加到项目中
//

import Foundation
import OnnxRuntimeBindings

/// Silero VAD 错误类型
enum SileroVADError: LocalizedError {
    case modelNotFound
    case sessionCreationFailed(Error)
    case inputCreationFailed
    case inferenceFailed(Error)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "VAD 模型文件未找到"
        case .sessionCreationFailed(let error):
            return "创建 ONNX 会话失败: \(error.localizedDescription)"
        case .inputCreationFailed:
            return "创建输入张量失败"
        case .inferenceFailed(let error):
            return "模型推理失败: \(error.localizedDescription)"
        case .invalidOutput:
            return "模型输出格式无效"
        }
    }
}

/// Silero VAD 检测结果
public struct VADResult {
    /// 语音概率 (0.0 - 1.0)
    public let probability: Float
    /// 是否为语音
    public let isSpeech: Bool
}

/// Silero VAD 模型封装
///
/// 使用 Silero VAD v4 或 v5 模型进行语音活动检测。
/// 模型需要 16kHz 单声道音频，每帧 512 采样点（32ms）。
///
/// 重要：模型实际需要 576 个采样点作为输入（512 当前帧 + 64 上下文采样点）
///
/// 使用示例：
/// ```swift
/// let vad = try SileroVAD(modelPath: "silero_vad.onnx")
/// let result = try vad.detect(audioFrame: floatSamples)
/// print("语音概率: \(result.probability)")
/// ```
public final class SileroVAD {

    // MARK: - Constants

    /// 采样率
    public static let sampleRate: Int = 16000

    /// 每帧采样点数（512 = 32ms @ 16kHz）
    public static let frameSize: Int = 512

    /// 上下文采样点数（16kHz 时为 64）
    /// 参考：https://github.com/snakers4/silero-vad/blob/master/files/silero_vad.onnx
    private static let contextSize: Int = 64

    /// 有效窗口大小 = 帧大小 + 上下文采样点数
    private static let effectiveWindowSize: Int = frameSize + contextSize  // 576

    /// 隐藏状态维度 (v5 模型使用 128，v4 使用 64)
    private static let hiddenSize: Int = 128

    /// 默认语音检测阈值
    public static let defaultThreshold: Float = 0.5

    // MARK: - Properties

    private let session: ORTSession
    private let env: ORTEnv

    /// 隐藏状态 h（LSTM）
    private var hiddenStateH: [Float]

    /// 隐藏状态 c（LSTM）
    private var hiddenStateC: [Float]

    /// 上下文采样点（来自上一帧的最后 64 个采样点）
    private var contextSamples: [Float]

    /// 语音检测阈值
    public var threshold: Float

    // MARK: - Initialization

    /// 初始化 Silero VAD
    /// - Parameters:
    ///   - modelPath: ONNX 模型文件路径
    ///   - threshold: 语音检测阈值，默认 0.5
    public init(modelPath: String, threshold: Float = defaultThreshold) throws {
        // 检查模型文件是否存在
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw SileroVADError.modelNotFound
        }

        // 创建 ONNX Runtime 环境
        self.env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)

        // 创建会话选项
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(1)
        try options.setGraphOptimizationLevel(ORTGraphOptimizationLevel.basic)

        // 创建推理会话
        do {
            self.session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        } catch {
            throw SileroVADError.sessionCreationFailed(error)
        }

        // 初始化隐藏状态
        self.hiddenStateH = Array(repeating: 0, count: Self.hiddenSize)
        self.hiddenStateC = Array(repeating: 0, count: Self.hiddenSize)

        // 初始化上下文采样点
        self.contextSamples = Array(repeating: 0, count: Self.contextSize)

        self.threshold = threshold

        print("[SileroVAD] Initialized with model: \(modelPath), effective window size: \(Self.effectiveWindowSize)")
    }

    /// 从 Bundle 资源初始化
    /// - Parameters:
    ///   - bundle: 资源所在的 Bundle，默认为 main bundle
    ///   - threshold: 语音检测阈值
    public convenience init(bundle: Bundle = .main, threshold: Float = defaultThreshold) throws {
        guard let modelPath = bundle.path(forResource: "silero_vad", ofType: "onnx") else {
            throw SileroVADError.modelNotFound
        }
        try self.init(modelPath: modelPath, threshold: threshold)
    }

    // MARK: - Detection

    /// 检测单帧音频是否包含语音
    /// - Parameter audioFrame: 音频帧数据（Float 数组，512 采样点）
    /// - Returns: VAD 检测结果
    public func detect(audioFrame: [Float]) throws -> VADResult {
        if audioFrame.count != Self.frameSize {
            print("[SileroVAD] Warning: Frame size mismatch. Expected \(Self.frameSize), got \(audioFrame.count)")
            // 继续处理，但可能会有问题
        }

        do {
            // 构建模型输入：上下文采样点 + 当前帧
            // 模型需要 576 个采样点：64 个上下文 + 512 个当前帧
            var modelInput = contextSamples  // 先添加上下文采样点（64 个）
            modelInput.append(contentsOf: audioFrame)  // 再添加当前帧（512 个）

            // 创建输入张量 - 形状为 [1, 576]
            let inputShape: [NSNumber] = [1, modelInput.count] as [NSNumber]
            var modelInputCopy = modelInput
            let inputData = NSData(bytes: &modelInputCopy, length: modelInput.count * MemoryLayout<Float>.stride)
            let inputTensor = try ORTValue(
                tensorData: NSMutableData(data: inputData as Data),
                elementType: ORTTensorElementDataType.float,
                shape: inputShape
            )

            // 创建采样率张量
            let srShape: [NSNumber] = [1]
            var srValue: Int64 = Int64(Self.sampleRate)
            let srData = NSData(bytes: &srValue, length: MemoryLayout<Int64>.size)
            let srTensor = try ORTValue(
                tensorData: NSMutableData(data: srData as Data),
                elementType: ORTTensorElementDataType.int64,
                shape: srShape
            )

            // 创建状态张量 (v5 使用单个 state 张量，形状 [2, 1, 128])
            let stateShape: [NSNumber] = [2, 1, Self.hiddenSize] as [NSNumber]
            var combinedState = hiddenStateH + hiddenStateC
            let stateData = NSData(bytes: &combinedState, length: Self.hiddenSize * 2 * MemoryLayout<Float>.stride)
            let stateTensor = try ORTValue(
                tensorData: NSMutableData(data: stateData as Data),
                elementType: ORTTensorElementDataType.float,
                shape: stateShape
            )

            // 运行推理 - v5 模型使用 "state" 和 "stateN"
            let inputs: [String: ORTValue] = [
                "input": inputTensor,
                "sr": srTensor,
                "state": stateTensor
            ]
            let outputNames: Set<String> = ["output", "stateN"]

            let outputs = try session.run(withInputs: inputs, outputNames: outputNames, runOptions: nil)

            // 获取输出
            guard let outTensor = outputs["output"],
                  let stateNTensor = outputs["stateN"] else {
                throw SileroVADError.invalidOutput
            }

            // 获取概率值
            let outputTensorData = try outTensor.tensorData()
            let outputPtr = outputTensorData.bytes.assumingMemoryBound(to: Float.self)
            let probability = outputPtr.pointee

            // 更新隐藏状态
            let stateNTensorData = try stateNTensor.tensorData()
            let floatPtr = stateNTensorData.bytes.assumingMemoryBound(to: Float.self)
            for i in 0..<Self.hiddenSize {
                hiddenStateH[i] = floatPtr[i]
                hiddenStateC[i] = floatPtr[i + Self.hiddenSize]
            }

            // 更新上下文采样点：保存当前帧的最后 64 个采样点，供下一帧使用
            if audioFrame.count >= Self.contextSize {
                contextSamples = Array(audioFrame.suffix(Self.contextSize))
            }

            return VADResult(
                probability: probability,
                isSpeech: probability >= threshold
            )

        } catch let error as SileroVADError {
            throw error
        } catch {
            throw SileroVADError.inferenceFailed(error)
        }
    }

    /// 重置模型状态（用于新的音频流）
    public func resetState() {
        hiddenStateH = Array(repeating: 0, count: Self.hiddenSize)
        hiddenStateC = Array(repeating: 0, count: Self.hiddenSize)
        contextSamples = Array(repeating: 0, count: Self.contextSize)
        print("[SileroVAD] State reset (including context samples)")
    }

    // MARK: - Batch Processing

    /// 批量处理音频数据
    /// - Parameters:
    ///   - audioData: 完整的音频数据（Float 数组）
    ///   - hopSize: 帧移，默认等于帧大小（无重叠）
    /// - Returns: 每帧的检测结果
    public func detectBatch(audioData: [Float], hopSize: Int = frameSize) -> [VADResult] {
        var results: [VADResult] = []
        var offset = 0

        while offset + Self.frameSize <= audioData.count {
            let frame = Array(audioData[offset..<offset + Self.frameSize])
            do {
                let result = try detect(audioFrame: frame)
                results.append(result)
            } catch {
                print("[SileroVAD] Detection error at offset \(offset): \(error)")
                results.append(VADResult(probability: 0, isSpeech: false))
            }
            offset += hopSize
        }

        return results
    }
}

// MARK: - Int16 Support

extension SileroVAD {

    /// 检测 Int16 格式的音频帧
    /// - Parameter int16Frame: Int16 格式的音频帧
    /// - Returns: VAD 检测结果
    public func detect(int16Frame: [Int16]) throws -> VADResult {
        let floatFrame = int16Frame.map { Float($0) / 32768.0 }
        return try detect(audioFrame: floatFrame)
    }

    /// 批量处理 Int16 格式的音频数据
    /// - Parameter int16Data: Int16 格式的音频数据
    /// - Returns: 每帧的检测结果
    public func detectBatch(int16Data: [Int16]) -> [VADResult] {
        let floatData = int16Data.map { Float($0) / 32768.0 }
        return detectBatch(audioData: floatData)
    }
}
