//
//  FeedbackView.swift
//  VoxLink
//
//  Help and feedback view for submitting user feedback
//

import SwiftUI

struct FeedbackView: View {
    @State private var subject = ""
    @State private var content = ""
    @State private var isSubmitting = false
    @State private var submitSuccess = false
    @State private var errorMessage: String?

    private let maxContentLength = 2000

    private var isValid: Bool {
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        content.count <= maxContentLength
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("帮助与反馈")
                .font(.system(size: 18, weight: .semibold))

            if submitSuccess {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("感谢您的反馈！")
                        .font(.headline)

                    Text("我们会尽快处理您的反馈")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("关闭") {
                        FeedbackWindowManager.shared.close()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Form
                VStack(alignment: .leading, spacing: 16) {
                    // Subject
                    VStack(alignment: .leading, spacing: 6) {
                        Text("主题")
                            .font(.system(size: 12, weight: .medium))
                        TextField("请输入反馈主题", text: $subject)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("内容")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(content.count)/\(maxContentLength)")
                                .font(.system(size: 11))
                                .foregroundColor(content.count > maxContentLength ? .red : .secondary)
                        }

                        TextEditor(text: $content)
                            .frame(minHeight: 150)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }

                    // Submit button
                    HStack {
                        Spacer()
                        Button("取消") {
                            FeedbackWindowManager.shared.close()
                        }
                        .buttonStyle(.bordered)

                        Button(action: submitFeedback) {
                            HStack(spacing: 6) {
                                if isSubmitting {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                }
                                Text("发送")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValid || isSubmitting)
                    }
                }

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 400, height: 400)
    }

    private func submitFeedback() {
        guard isValid else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let userEmail = SupabaseService.shared.userEmail
                try await FeedbackService.shared.submitFeedback(
                    subject: subject.trimmingCharacters(in: .whitespaces),
                    content: content.trimmingCharacters(in: .whitespaces),
                    email: userEmail
                )

                await MainActor.run {
                    submitSuccess = true
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "发送失败: \(error.localizedDescription)"
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FeedbackView()
}
