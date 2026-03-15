//
//  VADService.swift
//  VoxLink
//
//  VAD 服务层 - 提供统一的 VAD 功能访问入口
//
//  集成步骤：
//  1. 添加 ONNX Runtime Swift 依赖
//     - Xcode: File > Add Packages > https://github.com/microsoft/onnxruntime-swift-package-manager
//     - 版本: 1.16.0 或更高
//
//  2. 下载 Silero VAD 模型
//     - 地址: https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx
//     - 或使用: curl -O https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx
//
//  3. 将 silero_vad.onnx 添加到 Xcode 项目
//     - 勾选 "Copy items if needed"
//     - 确保在 "Target Membership" 中选中 VoxLinkAI
//

import Combine
import Foundation

/// VAD 服务错误
public enum VADServiceError: LocalizedError {
    case modelNotReady
    case processingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "VAD 模型未就绪"
        case .processingFailed(let error):
            return "VAD 处理失败: \(error.localizedDescription)"
        }
    }
}

/// VAD 服务
///
/// 单例模式，提供全局 VAD 功能访问。
///
/// 使用示例：
/// ```swift
/// let service = VADService.shared
///
/// // 初始化（在 App 启动时调用）
/// try await service.initialize()
///
/// // 处理音频数据
/// let result = try await service.process(audioData: pcmData)
/// for segment in result.segments {
///     print("语音: \(segment.startTime)s - \(segment.endTime)s")
/// }
/// ```
public final class VADService: ObservableObject {

    // MARK: - Singleton

    public static let shared = VADService()

    // MARK: - Published Properties

    /// 是否已初始化
    @Published public private(set) var isInitialized: Bool = false

    /// 是否正在处理
    @Published public private(set) var isProcessing: Bool = false

    /// 上次处理结果
    @Published public private(set) var lastResult: VADProcessResult?

    /// 错误信息
    @Published public private(set) var lastError: Error?

    // MARK: - Private Properties

    private var processor: VADProcessor?
    private let processingQueue = DispatchQueue(label: "com.voxlinkai.vadservice", qos: .userInitiated)

    /// 配置
    public var config: VADConfig {
        didSet {
            // 配置变更后需要重新创建处理器
            if isInitialized {
                reinitializeProcessor()
            }
        }
    }

    // MARK: - Initialization

    private init(config: VADConfig = VADConfig()) {
        self.config = config
    }

    // MARK: - Public Methods

    /// 初始化 VAD 服务
    /// - Returns: 是否成功初始化
    @discardableResult
    public func initialize() async throws -> Bool {
        guard !isInitialized else { return true }

        // 首先确保模型在持久位置
        ensureModelInPersistentLocation()

        // 获取所有可能的模型路径
        let modelPaths = getModelSearchPaths()

        for path in modelPaths {
            print("[VADService] Checking model path: \(path)")
            if FileManager.default.fileExists(atPath: path) {
                do {
                    processor = try VADProcessor(modelPath: path, config: config)
                    await MainActor.run {
                        self.isInitialized = true
                        self.lastError = nil
                    }
                    print("[VADService] Initialized successfully from: \(path)")
                    return true
                } catch {
                    print("[VADService] Failed to load model from \(path): \(error)")
                    continue
                }
            }
        }

        // 所有路径都失败
        let error = VADServiceError.modelNotReady
        await MainActor.run {
            self.lastError = error
        }
        print("[VADService] Model not found. Searched paths: \(modelPaths)")
        return false
    }

    /// 确保模型在持久位置（.voxlinkai 目录）
    private func ensureModelInPersistentLocation() {
        let voxlinkDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voxlinkai")
        let destPath = voxlinkDir.appendingPathComponent("silero_vad.onnx")

        // 如果已经存在，不需要复制
        if FileManager.default.fileExists(atPath: destPath.path) {
            return
        }

        // 查找源文件
        let sourcePaths = getModelSourcePaths()
        for sourcePath in sourcePaths {
            if FileManager.default.fileExists(atPath: sourcePath) {
                do {
                    // 确保目标目录存在
                    try FileManager.default.createDirectory(at: voxlinkDir, withIntermediateDirectories: true)
                    // 复制文件
                    try FileManager.default.copyItem(atPath: sourcePath, toPath: destPath.path)
                    print("[VADService] Copied model from \(sourcePath) to \(destPath.path)")
                    return
                } catch {
                    print("[VADService] Failed to copy model: \(error)")
                }
            }
        }
    }

    /// 获取模型可能的源路径（用于复制到持久位置）
    private func getModelSourcePaths() -> [String] {
        var paths: [String] = []

        // 1. Bundle main
        if let bundlePath = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") {
            paths.append(bundlePath)
        }

        // 2. Bundle resources 目录
        if let resourcePath = Bundle.main.resourcePath {
            paths.append((resourcePath as NSString).appendingPathComponent("silero_vad.onnx"))
        }

        // 3. macOS app bundle 内的 Resources 目录
        if let executablePath = Bundle.main.executablePath {
            let executableDir = (executablePath as NSString).deletingLastPathComponent
            let contentsDir = (executableDir as NSString).deletingLastPathComponent
            paths.append((contentsDir as NSString).appendingPathComponent("Resources/silero_vad.onnx"))
        }

        // 4. Torch hub 缓存目录（如果之前通过 Python torch.hub 下载过）
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let torchHubPaths = [
            "\(homeDir)/.cache/torch/hub/snakers4_silero-vad_master/src/silero_vad/data/silero_vad.onnx",
            "\(homeDir)/.cache/torch/hub/snakers4_silero-vad_master/files/silero_vad.onnx",
        ]
        paths.append(contentsOf: torchHubPaths)

        // 5. 开发时的源码目录
        #if DEBUG
        // 尝试从当前工作目录向上查找
        let currentDir = FileManager.default.currentDirectoryPath
        let possibleSourcePaths = [
            "\(currentDir)/VoxLinkAI/Resources/silero_vad.onnx",
            "\(currentDir)/../VoxLinkAI/Resources/silero_vad.onnx",
            "\(currentDir)/../../VoxLinkAI/Resources/silero_vad.onnx",
        ]
        paths.append(contentsOf: possibleSourcePaths)
        #endif

        return paths
    }

    /// 获取模型搜索路径
    private func getModelSearchPaths() -> [String] {
        var paths: [String] = []

        // 1. .voxlinkai 目录（优先，持久位置）
        let voxlinkDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voxlinkai").path
        paths.append((voxlinkDir as NSString).appendingPathComponent("silero_vad.onnx"))

        // 2. Bundle main (正常发布时)
        if let bundlePath = Bundle.main.path(forResource: "silero_vad", ofType: "onnx") {
            paths.append(bundlePath)
        }

        // 3. Bundle resources 目录
        if let resourcePath = Bundle.main.resourcePath {
            paths.append((resourcePath as NSString).appendingPathComponent("silero_vad.onnx"))
        }

        // 4. 可执行文件所在目录
        if let executablePath = Bundle.main.executablePath {
            let executableDir = (executablePath as NSString).deletingLastPathComponent
            paths.append((executableDir as NSString).appendingPathComponent("silero_vad.onnx"))

            // macOS app bundle 内的 Resources 目录
            let contentsDir = (executableDir as NSString).deletingLastPathComponent
            paths.append((contentsDir as NSString).appendingPathComponent("Resources/silero_vad.onnx"))
        }

        // 5. Documents 目录
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            paths.append(documentsPath.appendingPathComponent("silero_vad.onnx").path)
        }

        // 6. Torch hub 缓存目录
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append("\(homeDir)/.cache/torch/hub/snakers4_silero-vad_master/src/silero_vad/data/silero_vad.onnx")

        // 7. 开发时的源码 Resources 目录（仅 DEBUG）
        #if DEBUG
        let currentDir = FileManager.default.currentDirectoryPath
        let devPaths = [
            "\(currentDir)/VoxLinkAI/Resources/silero_vad.onnx",
            "\(currentDir)/../VoxLinkAI/Resources/silero_vad.onnx",
            "\(currentDir)/../../VoxLinkAI/Resources/silero_vad.onnx",
        ]
        paths.append(contentsOf: devPaths)
        #endif

        return paths
    }

    /// 处理音频数据
    /// - Parameter audioData: PCM 音频数据（16kHz, mono, 16-bit）
    /// - Returns: VAD 处理结果
    public func process(audioData: Data) async throws -> VADProcessResult {
        guard let processor = processor, isInitialized else {
            throw VADServiceError.modelNotReady
        }

        await MainActor.run {
            self.isProcessing = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: VADServiceError.modelNotReady)
                    return
                }

                do {
                    let result = try processor.process(audioData: audioData)
                    Task { @MainActor in
                        self.isProcessing = false
                        self.lastResult = result
                        self.lastError = nil
                    }
                    continuation.resume(returning: result)
                } catch {
                    Task { @MainActor in
                        self.isProcessing = false
                        self.lastError = error
                    }
                    continuation.resume(throwing: VADServiceError.processingFailed(error))
                }
            }
        }
    }

    /// 创建实时处理器
    public func createRealtimeProcessor() throws -> VADProcessor.RealtimeProcessor {
        guard let processor = processor, isInitialized else {
            throw VADServiceError.modelNotReady
        }
        return processor.createRealtimeProcessor()
    }

    /// 创建实时处理器（使用自定义配置）
    /// - Parameter customConfig: 自定义 VAD 配置
    /// - Returns: 实时处理器实例
    public func createRealtimeProcessor(customConfig: VADConfig) throws -> VADProcessor.RealtimeProcessor {
        guard let processor = processor, isInitialized else {
            throw VADServiceError.modelNotReady
        }
        return processor.createRealtimeProcessor(customConfig: customConfig)
    }

    /// 重置服务
    public func reset() {
        processor?.reset()
        Task { @MainActor in
            self.lastResult = nil
            self.lastError = nil
        }
    }

    // MARK: - Private Methods

    private func reinitializeProcessor() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                self.processor = try VADProcessor(bundle: .main, config: self.config)
                print("[VADService] Processor reinitialized with new config")
            } catch {
                print("[VADService] Failed to reinitialize: \(error)")
                Task { @MainActor in
                    self.isInitialized = false
                    self.lastError = error
                }
            }
        }
    }
}

// MARK: - Model Download Helper

extension VADService {

    /// 模型下载 URL
    public static let modelDownloadURL = "https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx"

    /// 检查模型是否存在
    public var isModelAvailable: Bool {
        // 检查所有搜索路径
        return getModelSearchPaths().contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// 下载模型到 .voxlink 目录
    public func downloadModel() async throws {
        guard let url = URL(string: Self.modelDownloadURL) else {
            throw VADServiceError.modelNotReady
        }

        // 使用 .voxlinkai 目录存储模型
        let voxlinkDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voxlinkai")

        // 确保目录存在
        try FileManager.default.createDirectory(at: voxlinkDir, withIntermediateDirectories: true)

        let destinationPath = voxlinkDir.appendingPathComponent("silero_vad.onnx")

        print("[VADService] Downloading model from \(url.absoluteString)")

        let (tempURL, _) = try await URLSession.shared.download(from: url)

        // 如果目标文件已存在，先删除
        if FileManager.default.fileExists(atPath: destinationPath.path) {
            try FileManager.default.removeItem(at: destinationPath)
        }

        // 移动到目标位置
        try FileManager.default.moveItem(at: tempURL, to: destinationPath)

        print("[VADService] Model downloaded to \(destinationPath.path)")

        // 重新初始化
        _ = try await initialize()
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension VADService {

    /// 使用测试数据验证 VAD 功能
    public func testWithSampleData() async throws -> VADProcessResult {
        // 生成 1 秒的测试音频数据（静音）
        let sampleRate = 16000
        let duration = 1.0
        let sampleCount = Int(Double(sampleRate) * duration)
        var testData = Data(capacity: sampleCount * 2)

        // 添加一些模拟语音的随机噪声
        for i in 0..<sampleCount {
            let noise: Int16
            if i > sampleRate / 4 && i < sampleRate / 2 {
                // 中间部分模拟语音
                noise = Int16.random(in: -5000...5000)
            } else {
                // 其他部分为静音
                noise = Int16.random(in: -100...100)
            }
            testData.append(contentsOf: withUnsafeBytes(of: noise) { Array($0) })
        }

        return try await process(audioData: testData)
    }
}
#endif
