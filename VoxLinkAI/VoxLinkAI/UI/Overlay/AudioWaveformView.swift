//
//  AudioWaveformView.swift
//  VoxLink
//
//  音频波形可视化 - 精美动态音波动画
//

import Combine
import SwiftUI

// MARK: - Dynamic Waveform View

/// 动态音波视图 - 精美流畅的音波动画
struct DynamicWaveformView: View {
    let audioLevel: CGFloat

    @State private var animatedLevel: CGFloat = 0
    @State private var phase: CGFloat = 0
    @State private var timer: Timer?

    // 中心高、两边低的配置
    private let centerFactors: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.7 + animatedLevel * 0.3))
                    .frame(width: 3, height: heightForBar(at: index))
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .onChange(of: audioLevel) { newValue in
            animatedLevel = animatedLevel + (newValue - animatedLevel) * 0.5
        }
    }

    private func heightForBar(at index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxExtraHeight: CGFloat = 35  // 进一步增大波动幅度

        // 基于音量和位置计算高度
        let centerFactor = centerFactors[index]
        let waveOffset = sin(phase + CGFloat(index) * 0.8) * 0.15

        let level = animatedLevel + waveOffset
        let height = baseHeight + maxExtraHeight * level * centerFactor

        return max(height, 4)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            phase += 0.3
            // 持续向目标值平滑过渡
            animatedLevel = animatedLevel + (audioLevel - animatedLevel) * 0.3
        }
    }
}

/// 波形条形状 - 带圆角的胶囊形
struct WaveformBarShape: Shape {
    let level: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { }
    }

    func path(in rect: CGRect) -> Path {
        let clampedLevel = min(max(level, 0.1), 1.0)
        let height = rect.height * clampedLevel
        let y = (rect.height - height) / 2

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: 0, y: y, width: rect.width, height: height),
            cornerSize: CGSize(width: 1.5, height: 1.5)
        )
        return path
    }
}

// MARK: - Audio Waveform View (Legacy)

/// 音频波形视图 - 响应音量变化的动态波形
struct AudioWaveformView: View {
    @Binding var audioLevel: CGFloat
    let barCount: Int
    let color: Color

    @State private var randomOffsets: [CGFloat] = []

    init(
        audioLevel: Binding<CGFloat>,
        barCount: Int = 5,
        color: Color = .white
    ) {
        self._audioLevel = audioLevel
        self.barCount = barCount
        self.color = color
        _randomOffsets = State(initialValue: (0..<barCount).map { _ in CGFloat.random(in: 0.7...1.0) })
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    audioLevel: audioLevel,
                    index: index,
                    totalBars: barCount,
                    color: color,
                    randomOffset: randomOffsets[safe: index] ?? 1.0
                )
            }
        }
        .onAppear {
            if randomOffsets.count != barCount {
                randomOffsets = (0..<barCount).map { _ in CGFloat.random(in: 0.7...1.0) }
            }
        }
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// 单个波形条 - 带有平滑动画
struct WaveformBar: View {
    let audioLevel: CGFloat
    let index: Int
    let totalBars: Int
    let color: Color
    let randomOffset: CGFloat

    @State private var animatedLevel: CGFloat = 0
    @State private var targetLevel: CGFloat = 0

    let animationTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.6)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 4, height: barHeight)
            .shadow(color: color.opacity(0.3), radius: 1, y: 0)
            .onReceive(animationTimer) { _ in
                let diff = targetLevel - animatedLevel
                if abs(diff) > 0.01 {
                    animatedLevel += diff * 0.35
                }
            }
            .onChange(of: audioLevel) { newValue in
                targetLevel = newValue
            }
            .onAppear {
                animatedLevel = audioLevel
                targetLevel = audioLevel
            }
    }

    private var barHeight: CGFloat {
        let centerIndex = Double(totalBars - 1) / 2.0
        let distanceFromCenter = abs(Double(index) - centerIndex)
        let centerFactor = 1.0 - (distanceFromCenter / (centerIndex + 1)) * 0.4

        // 增大基础高度和动态高度范围
        let baseHeight: CGFloat = 8
        let maxDynamicHeight: CGFloat = 24

        return baseHeight + maxDynamicHeight * animatedLevel * CGFloat(centerFactor) * randomOffset
    }
}

// MARK: - Live Audio Waveform

/// 实时音频波形（连接到 Publisher）
struct LiveAudioWaveform: View {
    let audioPublisher: AnyPublisher<CGFloat, Never>
    let color: Color

    @State private var audioLevel: CGFloat = 0
    @State private var cancellable: AnyCancellable?

    init(
        audioPublisher: AnyPublisher<CGFloat, Never>,
        color: Color = .white
    ) {
        self.audioPublisher = audioPublisher
        self.color = color
    }

    var body: some View {
        AudioWaveformView(
            audioLevel: $audioLevel,
            barCount: 5,
            color: color
        )
        .onAppear {
            self.cancellable = audioPublisher
                .receive(on: DispatchQueue.main)
                .sink { [self] level in
                    self.audioLevel = level
                }
        }
        .onDisappear {
            cancellable?.cancel()
            cancellable = nil
        }
    }
}

// MARK: - Pulsing Dot

/// 脉动圆点（录音状态指示）
struct PulsingDot: View {
    let color: Color
    let isPulsing: Bool

    @State private var isAnimated = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing && isAnimated ? 1.2 : 1.0)
            .opacity(isPulsing && isAnimated ? 0.8 : 1.0)
            .onAppear {
                if isPulsing {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        isAnimated = true
                    }
                }
            }
            .onChange(of: isPulsing) { newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        isAnimated = true
                    }
                } else {
                    isAnimated = false
                }
            }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // 动态波形
        DynamicWaveformView(audioLevel: 0.3)
            .padding()
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())

        DynamicWaveformView(audioLevel: 0.7)
            .padding()
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())

        DynamicWaveformView(audioLevel: 1.0)
            .padding()
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
