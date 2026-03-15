//
//  AboutView.swift
//  VoxLink
//
//  关于视图 - 菜单栏入口
//

import SwiftUI

struct AboutView: View {
    /// 从 Info.plist 读取版本号
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }

    /// 网站基础 URL（从配置读取）
    private var websiteBaseURL: String { SupabaseConfig.websiteBaseURL }

    var body: some View {
        VStack(spacing: 0) {
            // 应用信息（居中）
            VStack(spacing: 12) {
                // App 图标
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.voxlinkAccent)
                }

                Text("VoxLink AI")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(appVersion)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Copyright © 2026 VoxLink AI. All rights reserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            Divider()

            // 法律文档（左对齐，上下排列）— 仅在配置了网站 URL 时显示
            if !websiteBaseURL.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("法律文档")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    if let privacyURL = URL(string: "\(websiteBaseURL)/privacy") {
                        Link(destination: privacyURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.subheadline)
                                    .frame(width: 16)
                                Text("隐私政策")
                                    .font(.subheadline)
                            }
                        }
                    }

                    if let termsURL = URL(string: "\(websiteBaseURL)/terms") {
                        Link(destination: termsURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.fill")
                                    .font(.subheadline)
                                    .frame(width: 16)
                                Text("用户协议")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            }

            Divider()

            // 开源许可证（左对齐）
            VStack(alignment: .leading, spacing: 6) {
                Text("开源许可证")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Link(destination: URL(string: "https://github.com/supabase/supabase-swift")!) {
                    Text("Supabase Swift - MIT License")
                        .font(.caption)
                }

                Link(destination: URL(string: "https://github.com/microsoft/onnxruntime")!) {
                    Text("ONNX Runtime - MIT License")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
        .padding(20)
        .frame(width: 280)
    }
}

#Preview {
    AboutView()
}
