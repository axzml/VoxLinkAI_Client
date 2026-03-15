//
//  AudioCapture.swift
//  VoxLink
//
//  音频捕获 - 使用 AVAudioEngine
//

import AVFoundation
import Combine
import Foundation

/// 音频捕获服务
///
/// - Note: 并发安全设计说明
///   - `audioBuffer` 通过 `bufferLock` 保护，支持多线程安全访问
///   - `isCapturing` 和 `shouldAccumulateBuffer` 虽然无显式锁，但有隐式顺序保证：
///     - startCapture 先设置状态，再安装 tap → tap 回调开始时状态已确定
///     - stopCapture 先移除 tap，再读取状态 → 回调已停止，无竞争
///   - 此设计依赖调用方的顺序保证，未来如需更严格的并发安全可改用 actor
final class AudioCapture: @unchecked Sendable {
    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: [Int16] = []
    private let bufferLock = NSLock()

    /// 是否累积音频数据到缓冲区（服务器模式需要，直连模式不需要）
    /// - Note: 通过 startCapture/stopCapture 的顺序保证线程安全
    private var shouldAccumulateBuffer: Bool = false

    /// 音量级别发布者 (0.0 - 1.0)
    let audioLevelSubject = PassthroughSubject<CGFloat, Never>()
    var audioLevelPublisher: AnyPublisher<CGFloat, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    /// PCM 数据发布者
    let pcmDataSubject = PassthroughSubject<Data, Never>()
    var pcmDataPublisher: AnyPublisher<Data, Never> {
        pcmDataSubject.eraseToAnyPublisher()
    }

    private(set) var isCapturing = false
    private let captureQueue = DispatchQueue(label: "com.voxlinkai.audiocapture", qos: .userInitiated)

    /// 预热的转换器和输出格式（用于快速启动）
    private var preparedConverter: AVAudioConverter?
    private var preparedOutputFormat: AVAudioFormat?

    // MARK: - Public Methods

    /// 预热音频引擎（在应用启动或空闲时调用，减少首次录音延迟）
    func prepare() {
        guard audioEngine == nil else { return }

        // 创建音频引擎
        let engine = AVAudioEngine()
        self.audioEngine = engine
        self.inputNode = engine.inputNode

        // 获取输入格式
        let inputFormat = inputNode!.outputFormat(forBus: 0)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        // 创建格式转换器
        if let converter = AVAudioConverter(from: inputFormat, to: outputFormat) {
            self.preparedConverter = converter
            self.preparedOutputFormat = outputFormat
        }

        // 预热引擎（不启动音频流，只分配资源）
        engine.prepare()

        print("[AudioCapture] Audio engine prepared")
    }

    /// 开始捕获音频
    /// - Parameter accumulateBuffer: 是否累积音频数据到缓冲区（服务器模式需要，直连模式不需要）
    func startCapture(accumulateBuffer: Bool = false) throws {
        guard !isCapturing else { return }

        self.shouldAccumulateBuffer = accumulateBuffer

        // macOS 上检查麦克风权限
        #if os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status != .authorized {
            // 请求权限
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    print("[AudioCapture] Microphone permission denied")
                }
            }
            // 如果还没授权，继续尝试（系统会弹出权限请求）
        }
        #endif

        // 使用已预热的引擎，或创建新的
        if audioEngine == nil {
            // 没有预热的引擎，创建新的
            let engine = AVAudioEngine()
            self.audioEngine = engine
            self.inputNode = engine.inputNode

            let inputFormat = inputNode!.outputFormat(forBus: 0)
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            )!

            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw AudioCaptureError.converterCreationFailed
            }
            self.preparedConverter = converter
            self.preparedOutputFormat = outputFormat
        }

        guard let engine = audioEngine,
              let converter = preparedConverter,
              let outputFormat = preparedOutputFormat else {
            throw AudioCaptureError.converterCreationFailed
        }

        let inputFormat = inputNode!.outputFormat(forBus: 0)

        // 安装 tap
        inputNode!.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat
        ) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }

        // 启动引擎
        try engine.start()
        self.isCapturing = true
        bufferLock.lock()
        self.audioBuffer.removeAll()
        bufferLock.unlock()

        print("[AudioCapture] Started capturing audio")
    }

    /// 停止捕获音频
    func stopCapture() -> Data {
        guard isCapturing else { return Data() }

        // 停止引擎但保留实例以供下次快速启动
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        isCapturing = false

        // 返回收集的 PCM 数据
        bufferLock.lock()
        let pcmData = Data(bytes: audioBuffer, count: audioBuffer.count * 2)
        self.audioBuffer.removeAll()
        bufferLock.unlock()

        print("[AudioCapture] Stopped capturing, collected \(pcmData.count) bytes")
        return pcmData
    }

    // MARK: - Private Methods

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        captureQueue.async { [weak self] in
            guard let self = self else { return }

            // 计算输入帧数
            let inputFrameCount = buffer.frameLength
            let outputFrameCount = AVAudioFrameCount(
                Double(inputFrameCount) * outputFormat.sampleRate / buffer.format.sampleRate
            )

            // 创建输出缓冲区
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

            if let error = error {
                print("[AudioCapture] Conversion error: \(error)")
                return
            }

            // 提取 PCM 数据
            if let channelData = outputBuffer.int16ChannelData {
                let frameLength = Int(outputBuffer.frameLength)

                // 仅在服务器模式下累积到缓冲区
                if self.shouldAccumulateBuffer {
                    let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
                    self.bufferLock.lock()
                    self.audioBuffer.append(contentsOf: samples)
                    self.bufferLock.unlock()
                }

                // 发送 PCM 数据（用于实时处理）
                let data = Data(bytes: channelData[0], count: frameLength * 2)
                self.pcmDataSubject.send(data)

                // 计算音量级别
                self.calculateAudioLevel(from: channelData[0], frameCount: frameLength)
            }
        }
    }

    private func calculateAudioLevel(from samples: UnsafePointer<Int16>, frameCount: Int) {
        guard frameCount > 0 else { return }

        // 计算 RMS
        var sum: Double = 0
        for i in 0..<frameCount {
            let sample = Double(samples[i])
            sum += sample * sample
        }
        let rms = sqrt(sum / Double(frameCount))

        // 转换为 0.0 - 1.0 范围
        // 16-bit 音频最大值是 32767
        let level = min(rms / 16384.0, 1.0)

        DispatchQueue.main.async { [weak self] in
            self?.audioLevelSubject.send(CGFloat(level))
        }
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝"
        case .converterCreationFailed:
            return "无法创建音频转换器"
        }
    }
}
