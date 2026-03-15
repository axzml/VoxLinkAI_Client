//
//  LegalDocumentView.swift
//  VoxLink
//
//  法律文档展示视图 - 支持 Markdown 渲染
//  用于 NavigationLink 导航
//

import SwiftUI
import WebKit

/// 法律文档视图（用于导航）
struct LegalDocumentView: View {
    let title: String
    let markdownContent: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LegalMarkdownWebView(markdown: markdownContent)
                    .padding()
            }
        }
        .navigationTitle(title)
        .frame(minWidth: 600, minHeight: 500)
    }
}

/// Markdown WebView 渲染器（用于导航视图）
struct LegalMarkdownWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = markdownToHTML(markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }

    /// 将 Markdown 转换为 HTML
    private func markdownToHTML(_ markdown: String) -> String {
        var html = markdown

        // 标题
        html = html.replacingOccurrences(of: "^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)

        // 粗体
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)

        // 斜体
        html = html.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)

        // 列表项
        html = html.replacingOccurrences(of: "^- (.+)$", with: "<li>$1</li>", options: .regularExpression)

        // 水平线
        html = html.replacingOccurrences(of: "^---$", with: "<hr>", options: .regularExpression)

        // 段落处理
        let lines = html.components(separatedBy: "\n")
        var processedLines: [String] = []
        var inList = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<li>") {
                if !inList {
                    processedLines.append("<ul>")
                    inList = true
                }
                processedLines.append(line)
            } else {
                if inList {
                    processedLines.append("</ul>")
                    inList = false
                }
                if !trimmed.isEmpty &&
                   !trimmed.hasPrefix("<h") &&
                   !trimmed.hasPrefix("<hr") &&
                   !trimmed.hasPrefix("<ul") &&
                   !trimmed.hasPrefix("</ul") {
                    processedLines.append("<p>\(line)</p>")
                } else {
                    processedLines.append(line)
                }
            }
        }

        if inList {
            processedLines.append("</ul>")
        }

        html = processedLines.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: #333;
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 20px;
                }
                h1 { font-size: 24px; margin-top: 20px; margin-bottom: 10px; }
                h2 { font-size: 20px; margin-top: 25px; margin-bottom: 10px; border-bottom: 1px solid #eee; padding-bottom: 5px; }
                h3 { font-size: 16px; margin-top: 20px; margin-bottom: 8px; }
                p { margin: 10px 0; }
                ul { margin: 10px 0; padding-left: 25px; }
                li { margin: 5px 0; }
                hr { border: none; border-top: 1px solid #ddd; margin: 30px 0; }
                strong { color: #000; }
                a { color: #007AFF; text-decoration: none; }
            </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }
}

// MARK: - 预览

#Preview("Privacy Policy") {
    LegalDocumentView(
        title: "隐私政策",
        markdownContent: """
        # 隐私政策

        ## 1. 引言

        这是隐私政策的预览。

        ## 2. 我们收集的信息

        - 邮箱地址
        - 使用数据
        """
    )
}

#Preview("Terms of Service") {
    LegalDocumentView(
        title: "用户协议",
        markdownContent: """
        # 用户协议

        ## 1. 总则

        这是用户协议的预览。
        """
    )
}
