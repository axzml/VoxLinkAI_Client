//
//  OverlayView.swift
//  VoxLink
//
//  悬浮胶囊视图 - Dark Glassmorphism 设计风格
//

import Combine
import SwiftUI

/// Overlay 模式
enum OverlayMode {
    case dictation
    case translation
}

/// 悬浮胶囊视图
struct OverlayView: View {
    @ObservedObject var state: OverlayState

    /// 取消录音的回调
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            // 上层：状态指示 + 声波动画 + 关闭按钮
            HStack(spacing: 10) {
                // 状态指示点
                statusIndicator

                // 分隔线
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 16)

                // 声波动画
                waveformView

                // 关闭按钮（仅在录音状态显示）
                if state.status == .recording {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 1, height: 16)

                    cancelButton
                }
            }

            // 下层：实时转录文字（录音中和处理中都可以显示）
            if state.status == .recording || state.status == .processing {
                transcriptView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(glassmorphismBackground)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.15), radius: 40, x: 0, y: 20)
    }

    // MARK: - Cancel Button

    @ViewBuilder
    private var cancelButton: some View {
        Button(action: {
            onCancel?()
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help("取消录音")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIndicator: some View {
        switch state.status {
        case .recording:
            // 录音中：动态脉动红点（随音量跳动）
            RecordingIndicator(audioLevel: state.audioLevel)
                .frame(width: 24, height: 24)

        case .processing:
            // 处理中：旋转指示器
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.8)))
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)

        case .idle:
            // 空闲：灰色圆点
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private var waveformView: some View {
        switch state.status {
        case .recording:
            // 录音中：动态声波
            DynamicWaveformView(audioLevel: state.audioLevel)
                .frame(height: 20)

        case .processing:
            // 处理中：静态波纹
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 3, height: 8)
                }
            }
            .frame(height: 20)

        case .idle:
            // 空闲：VoxLink AI 文字
            Text("VoxLink AI")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var transcriptView: some View {
        if !state.transcript.isEmpty {
            Text(displayTranscript)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 280)
        } else {
            Text("正在聆听...")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    /// 显示的转录文本：只显示最后 35 个字符，确保始终显示最新内容
    private var displayTranscript: String {
        let text = state.transcript

        // 如果文本较短，直接显示
        if text.count <= 35 {
            return text
        }

        // 只显示最后 35 个字符，前面加省略号表示有更多内容
        return "…" + String(text.suffix(35))
    }

    // MARK: - Glassmorphism Background

    private var glassmorphismBackground: some View {
        ZStack {
            // 底层：深色半透明背景
            Color.black.opacity(0.6)

            // 中层：Material 磨砂效果
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.4)

            // 顶层：微妙的高光边缘
            RoundedRectangle(cornerRadius: 100)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

// MARK: - Recording Indicator

/// 录音指示器 - 随音量动态脉动
struct RecordingIndicator: View {
    let audioLevel: CGFloat

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: false)) { timeline in
            ZStack {
                // 最外层：扩散光晕（随音量变化）
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 24 * pulseScale, height: 24 * pulseScale)
                    .blur(radius: 4)

                // 中层：脉动环
                Circle()
                    .stroke(
                        Color.red.opacity(glowOpacity),
                        lineWidth: 2
                    )
                    .frame(width: 16 * pulseScale, height: 16 * pulseScale)

                // 内层：核心红点
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1, green: 0.3, blue: 0.3),
                                Color(red: 0.9, green: 0.15, blue: 0.15)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 4
                        )
                    )
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.6), radius: 2, x: 0, y: 0)
            }
            .onChange(of: timeline.date) { _ in
                updatePulse()
            }
        }
    }

    private func updatePulse() {
        // 平滑过渡到目标值
        let targetScale = 1.0 + audioLevel * 0.8
        let targetGlow = 0.3 + Double(audioLevel) * 0.5

        withAnimation(.easeOut(duration: 0.08)) {
            pulseScale = pulseScale + (targetScale - pulseScale) * 0.4
            glowOpacity = glowOpacity + (targetGlow - glowOpacity) * 0.4
        }
    }
}

// MARK: - Overlay State

/// Overlay 状态
enum OverlayStatus {
    case idle
    case recording
    case processing
}

/// Overlay 状态对象
class OverlayState: ObservableObject {
    @Published var status: OverlayStatus = .idle
    @Published var audioLevel: CGFloat = 0
    @Published var transcript: String = ""
    @Published var processingText: String = "处理中..."
    @Published var isPulsing: Bool = false

    static let shared = OverlayState()

    init() {}

    func startPulsing() {
        isPulsing = true
    }

    func stopPulsing() {
        isPulsing = false
    }
}

// MARK: - Preview

#Preview("Recording State") {
    ZStack {
        // 模拟壁纸背景
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 30) {
            // 空闲状态
            OverlayView(state: {
                let state = OverlayState()
                state.status = .idle
                return state
            }())

            // 录音状态（有转录文字）
            OverlayView(state: {
                let state = OverlayState()
                state.status = .recording
                state.audioLevel = 0.6
                state.transcript = "你好，这是一段测试文字"
                state.isPulsing = true
                return state
            }())

            // 录音状态（无转录文字）
            OverlayView(state: {
                let state = OverlayState()
                state.status = .recording
                state.audioLevel = 0.3
                state.transcript = ""
                state.isPulsing = true
                return state
            }())

            // 处理状态
            OverlayView(state: {
                let state = OverlayState()
                state.status = .processing
                state.processingText = "润色中..."
                return state
            }())
        }
    }
    .frame(width: 500, height: 400)
}
