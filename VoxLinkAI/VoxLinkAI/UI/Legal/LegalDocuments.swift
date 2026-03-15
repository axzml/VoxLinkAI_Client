//
//  LegalDocuments.swift
//  VoxLink
//
//  法律文档加载工具
//

import Foundation

/// 法律文档管理
enum LegalDocuments {
    /// 加载隐私政策
    static func loadPrivacyPolicy() -> String {
        loadMarkdown(name: "PrivacyPolicy", subdirectory: "Legal")
    }

    /// 加载用户协议
    static func loadTermsOfService() -> String {
        loadMarkdown(name: "TermsOfService", subdirectory: "Legal")
    }

    /// 加载 Markdown 文件
    private static func loadMarkdown(name: String, subdirectory: String? = nil) -> String {
        // 搜索路径列表（按优先级）
        let searchPaths: [(name: String, ext: String, subdirectory: String?)] = [
            // 1. 尝试指定子目录 (folder reference 方式)
            (name, "md", subdirectory),
            // 2. 尝试 Resources 子目录
            (name, "md", "Resources/\(subdirectory ?? "")"),
            // 3. 尝试无子目录 (group 方式 - 文件在 bundle 根目录)
            (name, "md", nil),
        ]

        for searchPath in searchPaths {
            if let url = Bundle.main.url(forResource: searchPath.name, withExtension: searchPath.ext, subdirectory: searchPath.subdirectory) {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    print("[LegalDocuments] Loaded \(name).md from: \(url.path)")
                    return content
                }
            }
        }

        // 调试：打印 bundle 中可用的 .md 文件
        print("[LegalDocuments] Available .md files in bundle:")
        if let resourcePath = Bundle.main.resourcePath {
            let fileManager = FileManager.default
            if let enumerator = fileManager.enumerator(atPath: resourcePath) {
                for case let file as String in enumerator {
                    if file.hasSuffix(".md") {
                        print("  - \(file)")
                    }
                }
            }
        }

        // 返回默认内容
        print("[LegalDocuments] Failed to load \(name).md")
        return """
        # 文档加载失败 / Document Load Error

        无法加载法律文档。请访问我们的网站查看最新版本。

        Unable to load legal document. Please visit our website for the latest version.

        **联系方式 / Contact:** support@voxlinkai.com
        """
    }
}
