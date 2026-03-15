# VAD 模块集成指南

## 概述

VAD（Voice Activity Detection）模块使用 Silero VAD 模型检测音频中的人声片段，用于长时录音功能的人声预处理。

## 文件结构

```
Core/VAD/
├── SileroVAD.swift      # Silero VAD 模型封装（ONNX Runtime）
├── VADProcessor.swift   # 音频处理管道
├── VADService.swift     # 服务层入口
└── README.md            # 本文件

Resources/
└── silero_vad.onnx      # Silero VAD 模型文件
```

## 集成步骤

### 1. 添加 ONNX Runtime Swift 依赖

在 Xcode 中：

1. 打开 `VoxLinkAI.xcodeproj`
2. 菜单: **File > Add Packages...**
3. 输入 URL: `https://github.com/microsoft/onnxruntime-swift-package-manager`
4. 选择版本: `1.16.0` 或更高（或使用最新版本）
5. 点击 **Add Package**
6. 确保勾选以下库添加到 VoxLinkAI target:
   - ✅ onnxruntime
   - ✅ onnxruntime_extensions

### 2. 添加模型文件到项目

模型文件 `silero_vad.onnx` 需要添加到 Xcode 项目：

1. 下载模型：`curl -O https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx`
2. 在 Xcode 项目导航器中，右键点击 `Resources` 文件夹
3. 选择 **Add Files to "VoxLinkAI"...**
4. 选择 `silero_vad.onnx` 文件
5. 确保勾选:
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ VoxLinkAI target (Target Membership)
6. 点击 **Add**

### 3. 添加源文件到项目

VAD 源文件已创建在 `Core/VAD/` 目录，需要添加到 Xcode 项目：

1. 在 Xcode 项目导航器中，右键点击 `Core` 文件夹
2. 选择 **Add Files to "VoxLinkAI"...**
3. 选择 `VAD` 文件夹
4. 确保勾选:
   - ✅ Create groups
   - ✅ VoxLinkAI target
5. 点击 **Add**

## 使用方法

### 初始化

```swift
// 在 App 启动时初始化 VAD 服务
Task {
    try? await VADService.shared.initialize()
}
```

### 处理音频数据

```swift
let service = VADService.shared

// 处理 PCM 音频数据（16kHz, mono, 16-bit signed）
let result = try await service.process(audioData: pcmData)

// 获取语音片段
for segment in result.segments {
    print("语音: \(segment.startTime)s - \(segment.endTime)s, 时长: \(segment.duration)s")

    // segment.audioData 包含该片段的音频数据
    // 可以直接发送给 ASR API
}
```

### 实时处理

```swift
// 创建实时处理器
let realtimeProcessor = try VADService.shared.createRealtimeProcessor()

// 设置回调
realtimeProcessor.onSpeechSegmentDetected = { segment in
    print("检测到语音片段: \(segment.startTime)s - \(segment.endTime)s")
}

// 处理音频帧（每帧 512 采样点）
realtimeProcessor.processFrame(audioFrame)
```

## 配置参数

```swift
var config = VADConfig()
config.speechThreshold = 0.5      // 语音检测阈值（0-1）
config.silencePadding = 0.3       // 静音填充时长（秒）
config.minSpeechDuration = 0.2    // 最小语音片段时长（秒）

VADService.shared.config = config
```

## 性能指标

- 模型大小: 291KB
- 单帧处理延迟: < 1ms
- 内存占用: < 10MB
- 适合长时间后台运行

## 参考资料

- [Silero VAD GitHub](https://github.com/snakers4/silero-vad)
- [ONNX Runtime Swift](https://github.com/microsoft/onnxruntime-swift)
