//
//  AliyunAIClient.swift
//  VoxLink
//
//  阿里云通义千问 AI 客户端 - 使用 OpenAI 兼容 API
//

import Foundation

/// AI 处理结果
struct AIProcessResult {
    let success: Bool
    let polished: String?       // 润色后的文本
    let intent: String?         // 意图类型: NONE, TRANSLATE
    let result: String?         // 翻译结果（如果有）
    let finalOutput: String     // 最终输出
    let error: String?

    /// 获取最终输出
    /// - 如果是翻译意图，返回翻译结果
    /// - 否则返回润色结果（或原始文本）
    static func getFinalOutput(
        transcript: String,
        polished: String?,
        intent: String?,
        result: String?
    ) -> String {
        // 如果是翻译意图且有翻译结果，返回翻译
        if intent == "TRANSLATE", let translateResult = result, !translateResult.isEmpty {
            return translateResult
        }
        // 否则返回润色结果，如果没有润色则返回原始文本
        return polished ?? transcript
    }
}

/// 阿里云通义千问 AI 客户端
final class AliyunAIClient {
    // MARK: - Configuration

    private let apiKey: String
    private let model: String
    private let session: URLSession

    /// API URL（OpenAI 兼容模式）
    private let apiURL = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    /// 系统提示词（优化版本，强调去除语气词）
    private let systemPrompt = """
你是一个智能语音助手，负责处理用户的语音输入。请按以下步骤处理：

【第一步：润色文本】
你必须彻底删除所有填充词和语气词，包括但不限于：
- 呃、嗯、啊、哦、呃、额
- 那个、这个、就是、其实、怎么说呢
- 也就是说、换句话说、然后呢
- 重复的词语和结巴

处理要求:
1. 删除所有上述填充词，不要保留任何语气词
2. 处理自我更正（只保留最后的说法）
3. 修正语法错误
4. 添加正确的标点符号
5. 保持原文语义和关键信息不变
6. 使句子通顺流畅

【第二步:识别意图】
分析润色后的文本，判断用户的意图:
- TRANSLATE: 用户明确要求翻译
- NONE: 普通陈述，没有特殊指令

【第三步:执行】
- 如果意图是 TRANSLATE，执行翻译（默认英语）
- 如果意图是 NONE，不需要额外处理

【输出格式】必须严格返回以下 JSON 格式，不要有任何额外文字:
{"intent": "意图类型", "polished": "润色后的文本（必须已删除所有语气词）", "result": "翻译结果/空字符串"}
"""

    // MARK: - Initialization

    /// 使用 API Key 初始化（自备 Key 模式）
    init(apiKey: String, model: String = "qwen3.5-plus") {
        self.apiKey = apiKey
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// 处理文本（润色 + 意图识别 + 翻译）
    func process(
        text: String,
        enablePolish: Bool = true,
        enableTranslate: Bool = false,
        targetLanguage: String = "English"
    ) async throws -> AIProcessResult {
        print("[AliyunAI] Processing text: \(text.prefix(50))...")

        // 构建用户提示
        var userPrompt = text
        if enableTranslate {
            userPrompt = "请将以下内容翻译成\(targetLanguage)：\n\(text)"
        }

        // 构建请求
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 设置授权信息（仅支持 API Key 模式）
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 8192,
            "enable_thinking": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        // 发送请求
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return AIProcessResult(
                success: false,
                polished: nil,
                intent: nil,
                result: nil,
                finalOutput: text,
                error: "无效的响应"
            )
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[AliyunAI] API error (\(httpResponse.statusCode)): \(errorMessage)")
            return AIProcessResult(
                success: false,
                polished: nil,
                intent: nil,
                result: nil,
                finalOutput: text,
                error: "API 错误 (\(httpResponse.statusCode))"
            )
        }

        // 解析响应
        return try parseResponse(data, originalText: text)
    }

    // MARK: - Private Methods

    private func parseResponse(_ data: Data, originalText: String) throws -> AIProcessResult {
        // 解析 OpenAI 格式的响应
        struct OpenAIResponse: Codable {
            let choices: [Choice]

            struct Choice: Codable {
                let message: Message

                struct Message: Codable {
                    let content: String
                }
            }
        }

        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            return AIProcessResult(
                success: false,
                polished: nil,
                intent: nil,
                result: nil,
                finalOutput: originalText,
                error: "无响应内容"
            )
        }

        print("[AliyunAI] Raw response: \(content.prefix(200))...")

        // 尝试解析 JSON
        var polished: String? = nil
        var intent: String? = nil
        var result: String? = nil

        if let jsonData = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            polished = json["polished"] as? String
            intent = json["intent"] as? String
            result = json["result"] as? String
        }

        // 如果 JSON 解析失败，直接使用原始内容作为润色结果
        if polished == nil {
            polished = content
            intent = "NONE"
            result = nil
        }

        // 计算最终输出
        let finalOutput = AIProcessResult.getFinalOutput(
            transcript: originalText,
            polished: polished,
            intent: intent,
            result: result
        )

        return AIProcessResult(
            success: true,
            polished: polished,
            intent: intent,
            result: result,
            finalOutput: finalOutput,
            error: nil
        )
    }
}

