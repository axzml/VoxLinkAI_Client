//
//  ASRClient.swift
//  VoxLink
//
//  ASR 客户端错误定义
//

import Foundation

// MARK: - Errors

enum ASRClientError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case encodingError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无效的服务器响应"
        case .httpError(let code):
            return "HTTP 错误: \(code)"
        case .encodingError:
            return "编码错误"
        case .serverError(let message):
            return "服务器错误: \(message)"
        }
    }
}
