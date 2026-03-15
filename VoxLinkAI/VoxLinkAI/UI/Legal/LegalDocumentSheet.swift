//
//  LegalDocumentSheet.swift
//  VoxLink
//
//  法律文档 Sheet 视图
//

import SwiftUI
import WebKit

/// 法律文档 Sheet 视图
struct LegalDocumentSheet: View {
    let title: String
    let content: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 内容区域 - 使用 WebView 渲染 Markdown
            SimpleMarkdownWebView(markdown: content)
                .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

/// 简单的 Markdown WebView 渲染器
struct SimpleMarkdownWebView: NSViewRepresentable {
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

    private func markdownToHTML(_ markdown: String) -> String {
        var html = markdown

        // 标题
        html = html.replacingOccurrences(of: "^### (.+)$", with: "<h3>$1</h3>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^## (.+)$", with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: "^# (.+)$", with: "<h1>$1</h1>", options: .regularExpression)

        // 粗体
        html = html.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)

        // 列表项
        html = html.replacingOccurrences(of: "^- (.+)$", with: "<li>$1</li>", options: .regularExpression)

        // 水平线
        html = html.replacingOccurrences(of: "^---$", with: "<hr>", options: .regularExpression)

        // 处理段落
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
                if !trimmed.isEmpty && !trimmed.hasPrefix("<h") && !trimmed.hasPrefix("<hr") {
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

#Preview("Privacy Policy") {
    LegalDocumentSheet(
        title: "隐私政策",
        content: """
        # 隐私政策

        ## 1. 引言

        这是隐私政策的预览。

        ## 2. 我们收集的信息

        - 邮箱地址
        - 使用数据
        """
    )
}
