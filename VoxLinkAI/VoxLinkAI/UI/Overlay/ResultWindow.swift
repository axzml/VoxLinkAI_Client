//
//  ResultWindow.swift
//  VoxLink
//
//  结果展示窗口 - Dark Glassmorphism 设计风格
//

import AppKit
import SwiftUI

/// 结果窗口管理器
@MainActor
final class ResultWindowManager {
    static let shared = ResultWindowManager()

    private var window: NSPanel?
    private var hostingView: NSHostingView<ResultWindowView>?

    private init() {}

    /// 显示结果窗口
    func show(result: TranscriptionResult, typingService: TypingService) {
        // 如果窗口已存在，先关闭
        close()

        // 创建 SwiftUI 视图
        // text: 原始转录（用于"原文"显示）
        // polished: 润色结果（用于"润色结果"显示）
        let view = ResultWindowView(
            text: result.originalText ?? result.text ?? "",
            polished: result.polished,
            onCopy: { [weak self] in
                self?.copyToClipboard(result.text ?? "")
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        hostingView = NSHostingView(rootView: view)

        // 创建无边框 Panel - 固定窗口大小
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 配置面板属性
        panel.contentView = hostingView
        panel.center()
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.makeKeyAndOrderFront(nil)

        // 激活应用但不抢焦点
        NSApp.activate(ignoringOtherApps: false)

        self.window = panel
    }

    /// 关闭窗口
    func close() {
        window?.close()
        window = nil
        hostingView = nil
    }

    /// 复制到剪贴板
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[ResultWindow] Text copied to clipboard")

        // 复制后自动关闭窗口
        close()
    }
}

// MARK: - SwiftUI View

struct ResultWindowView: View {
    let text: String
    let polished: String?
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var copyButtonHovered = false

    // MARK: - Layout Constants

    private let windowWidth: CGFloat = 400
    private let windowHeight: CGFloat = 320
    private let headerHeight: CGFloat = 44
    private let footerHeight: CGFloat = 56
    private let horizontalPadding: CGFloat = 20

    // 内容区域高度
    private var contentAreaHeight: CGFloat {
        windowHeight - headerHeight - footerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏（固定高度）
            headerView
                .frame(height: headerHeight)

            // 内容区域（固定高度）
            contentView
                .frame(height: contentAreaHeight)

            // 底部按钮区域（固定高度）
            footerView
                .frame(height: footerHeight)
        }
        .frame(width: windowWidth, height: windowHeight)
        .background(glassmorphismBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 15)
        .shadow(color: Color.black.opacity(0.2), radius: 60, x: 0, y: 30)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                // 成功图标
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.8),
                                Color.green.opacity(0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    )

                Text("润色完成")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()

            // 关闭按钮（增大点击区域）
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 24, height: 24)  // 扩大点击区域
                    .contentShape(Rectangle())    // 确保整个区域可点击
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
    }

    @ViewBuilder
    private var contentView: some View {
        if let polished = polished, !polished.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // 原文区域（约 1/3 高度）
                VStack(alignment: .leading, spacing: 4) {
                    Text("原文")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(0.5)

                    ScrollView {
                        Text(text)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(4)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .frame(height: contentAreaHeight * 0.35)

                // 分隔线
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, horizontalPadding)

                // 润色结果（约 2/3 高度）
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundColor(.blue.opacity(0.7))

                        Text("润色结果")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue.opacity(0.7))
                            .tracking(0.5)
                    }

                    ScrollView {
                        Text(polished)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(height: contentAreaHeight * 0.65)
            }
        } else {
            // 只有原文
            VStack(alignment: .leading, spacing: 6) {
                Text("转录结果")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .tracking(0.5)

                ScrollView {
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var footerView: some View {
        VStack(spacing: 0) {
            // 分隔线
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // 按钮区域
            HStack {
                Spacer()

                Button(action: onCopy) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text("复制")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(copyButtonHovered ? .white : .white.opacity(0.85))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: copyButtonHovered
                                        ? [Color.white.opacity(0.22), Color.white.opacity(0.12)]
                                        : [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    copyButtonHovered = hovering
                }

                Spacer()
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Glassmorphism Background

    private var glassmorphismBackground: some View {
        ZStack {
            // 底层：深色半透明背景
            Color.black.opacity(0.75)

            // 中层：Material 磨砂效果
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.5)
        }
    }
}

// MARK: - Preview

#Preview("Result Window") {
    ZStack {
        // 模拟壁纸背景
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 30) {
            // 有润色结果（短文本）
            ResultWindowView(
                text: "呃，这个是一个测试的文字",
                polished: "这是一个测试文字。",
                onCopy: {},
                onClose: {}
            )

            // 有润色结果（长文本）
            ResultWindowView(
                text: "呃，这个是一个非常长的测试文字，用于测试当用户说了很多话的时候，窗口布局是否会保持稳定，不会出现元素被挤压或者不可见的情况，我们需要确保无论文本多长，窗口的整体布局都能保持协调美观。",
                polished: "这是一个非常长的测试文字，用于验证当用户说了很多话时，窗口布局是否能保持稳定。我们需要确保无论文本多长，窗口的整体布局都能保持协调美观，不会出现元素被挤压或不可见的情况。通过固定高度和滚动区域，可以很好地解决这个问题。",
                onCopy: {},
                onClose: {}
            )

            // 只有原文
            ResultWindowView(
                text: "这是没有润色的原始文本。",
                polished: nil,
                onCopy: {},
                onClose: {}
            )
        }
        .padding()
    }
    .frame(width: 500, height: 800)
}
