//
//  FeedbackService.swift
//  VoxLink
//
//  Service for submitting user feedback to server
//

import Combine
import Foundation

/// Service for submitting user feedback
@MainActor
class FeedbackService: ObservableObject {
    static let shared = FeedbackService()

    @Published var isSubmitting: Bool = false

    private let apiBaseURL: String

    private init() {
        self.apiBaseURL = SettingsStore.shared.apiBaseURL
    }

    /// Submit feedback to server
    /// - Parameters:
    ///   - subject: Feedback subject
    ///   - content: Feedback content
    ///   - email: User email (optional)
    func submitFeedback(subject: String, content: String, email: String?) async throws {
        guard !isSubmitting else { return }

        guard !apiBaseURL.isEmpty else {
            throw FeedbackError.serviceNotConfigured
        }

        isSubmitting = true
        defer { isSubmitting = false }

        guard let url = URL(string: "\(apiBaseURL)/api/v1/feedback") else {
            throw FeedbackError.invalidRequest
        }

        var requestBody: [String: Any] = [
            "subject": subject,
            "content": content
        ]

        if let email = email, !email.isEmpty {
            requestBody["email"] = email
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token if available (使用 Supabase JWT)
        if let token = await SupabaseService.shared.getAccessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedbackError.networkError
        }

        if httpResponse.statusCode == 200 {
            // Success
            print("[FeedbackService] Feedback submitted successfully")
        } else {
            // Parse error
            if let errorResponse = try? JSONDecoder().decode(FeedbackErrorResponse.self, from: data) {
                throw FeedbackError.serverError(errorResponse.error)
            } else {
                throw FeedbackError.serverError("服务器错误 (\(httpResponse.statusCode))")
            }
        }
    }
}

// MARK: - Response Models

private struct FeedbackErrorResponse: Codable {
    let error: String
}

// MARK: - Errors

enum FeedbackError: Error, LocalizedError {
    case networkError
    case serverError(String)
    case invalidRequest
    case serviceNotConfigured

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "网络错误"
        case .serverError(let message):
            return message
        case .invalidRequest:
            return "无效请求"
        case .serviceNotConfigured:
            return "反馈服务未配置，请在 Secrets.plist 中设置 API_BASE_URL"
        }
    }
}
