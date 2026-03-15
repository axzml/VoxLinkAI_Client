//
//  AIPolishService.swift
//  VoxLink
//
//  AI 润色服务 - 用于对思维段转录文本进行润色
//

import Foundation

/// AI 润色服务
@MainActor
final class AIPolishService {
    // MARK: - Singleton

    static let shared = AIPolishService()

    // MARK: - Properties

    /// API URL（OpenAI 兼容模式）
    private let apiURL = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    private let session: URLSession

    /// 润色系统提示词（针对长文本优化）
    private let polishPrompt = """
你是一个专业的文字编辑助手。你的任务是对语音转文字的内容进行润色。

请按以下要求处理：
1. 删除所有填充词和语气词（如：呃、嗯、啊、哦、那个、这个、就是、其实等）
2. 修正语法错误和不通顺的表达
3. 添加正确的标点符号
4. 合理分段，使结构更清晰
5. 保持原文语义和关键信息不变
6. 使句子通顺流畅，符合书面语规范

注意：
- 不要改变原文的意思
- 不要添加原文没有的内容
- 保持口语化转为书面语的自然过渡
- 如果原文已经很通顺，可以保持原样

请直接输出润色后的文本，不要有任何额外说明。
"""

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// 润色文本
    /// - Parameter text: 原始文本
    /// - Returns: 润色后的文本，如果失败则返回 nil
    func polish(_ text: String) async -> String? {
        guard let apiKey = APIKeyStore.shared.aliyunASRAPIKey, !apiKey.isEmpty else {
            print("[AIPolishService] No API key configured")
            return nil
        }

        guard !text.isEmpty else {
            print("[AIPolishService] Empty text, skipping polish")
            return nil
        }

        print("[AIPolishService] Polishing text (\(text.count) chars)...")

        do {
            let polished = try await polishText(text, apiKey: apiKey)
            print("[AIPolishService] Polished successfully")
            return polished
        } catch {
            print("[AIPolishService] Polish failed: \(error)")
            return nil
        }
    }

    // MARK: - Private Methods

    private func polishText(_ text: String, apiKey: String) async throws -> String {
        // 构建请求
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "qwen3.5-plus",
            "messages": [
                ["role": "system", "content": polishPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 8192,
            "enable_thinking": false  // 使用非思考模式，响应更快
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // 发送请求
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIPolishService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[AIPolishService] API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw NSError(domain: "AIPolishService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API 错误"])
        }

        // 解析响应
        struct OpenAIResponse: Codable {
            let choices: [Choice]

            struct Choice: Codable {
                let message: Message

                struct Message: Codable {
                    let content: String
                }
            }
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = openAIResponse.choices.first?.message.content else {
            throw NSError(domain: "AIPolishService", code: -1, userInfo: [NSLocalizedDescriptionKey: "无响应内容"])
        }

        print("[AIPolishService] Polished text (\(content.count) chars)")
        return content
    }
}
