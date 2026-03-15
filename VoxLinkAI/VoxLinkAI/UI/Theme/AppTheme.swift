//
//  AppTheme.swift
//  VoxLink
//
//  主题定义 - 颜色、间距、材质
//

import SwiftUI

// MARK: - Color Extensions

extension Color {
    /// VoxLink 品牌色 - 青绿色
    static let voxlinkAccent = Color(
        red: 0.2,
        green: 0.85,
        blue: 0.7
    )

    /// 录音状态红色
    static let recordingRed = Color(
        red: 1.0,
        green: 0.35,
        blue: 0.35
    )

    /// 处理中状态黄色
    static let processingYellow = Color(
        red: 1.0,
        green: 0.8,
        blue: 0.3
    )

    /// 成功绿色
    static let successGreen = Color(
        red: 0.3,
        green: 0.85,
        blue: 0.5
    )
}

// MARK: - Theme

struct AppTheme {
    struct Palette {
        let background: Color
        let cardBackground: Color
        let cardBorder: Color
        let primaryText: Color
        let secondaryText: Color
        let accent: Color

        static let dark = Palette(
            background: Color(red: 0.08, green: 0.08, blue: 0.08),
            cardBackground: Color(red: 0.1, green: 0.1, blue: 0.1),
            cardBorder: Color.white.opacity(0.1),
            primaryText: Color.white.opacity(0.9),
            secondaryText: Color.white.opacity(0.6),
            accent: .voxlinkAccent
        )
    }

    struct Metrics {
        struct Spacing {
            static let xs: CGFloat = 4
            static let sm: CGFloat = 8
            static let md: CGFloat = 12
            static let lg: CGFloat = 16
            static let xl: CGFloat = 20
        }

        struct CornerRadius {
            static let sm: CGFloat = 8
            static let md: CGFloat = 12
            static let lg: CGFloat = 18
            static let pill: CGFloat = 999
        }

        struct Shadow {
            static let subtle = (
                color: Color.black.opacity(0.7),
                radius: CGFloat(12),
                x: CGFloat(0),
                y: CGFloat(6)
            )
        }
    }

    static let palette = Palette.dark
}

// MARK: - View Modifiers

/// 胶囊样式修饰器
struct CapsuleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                // 深色磨砂背景
                RoundedRectangle(cornerRadius: AppTheme.Metrics.CornerRadius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Metrics.CornerRadius.lg, style: .continuous)
                            .fill(Color.black.opacity(0.5))
                    }
                    .overlay {
                        // 微妙边框
                        RoundedRectangle(cornerRadius: AppTheme.Metrics.CornerRadius.lg, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .shadow(
                        color: AppTheme.Metrics.Shadow.subtle.color,
                        radius: AppTheme.Metrics.Shadow.subtle.radius,
                        x: AppTheme.Metrics.Shadow.subtle.x,
                        y: AppTheme.Metrics.Shadow.subtle.y
                    )
            }
    }
}

extension View {
    func capsuleStyle() -> some View {
        modifier(CapsuleStyle())
    }
}
