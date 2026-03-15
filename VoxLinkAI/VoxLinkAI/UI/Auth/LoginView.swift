//
//  LoginView.swift
//  VoxLink
//
//  登录界面 - 邮箱验证码登录
//  设计风格：简洁、优雅、符合 Apple Human Interface Guidelines
//

import AppKit
import Combine
import SwiftUI

/// 登录视图状态
private enum LoginStep {
    case email
    case otp
}

/// 焦点字段
private enum FocusField {
    case email
    case otp
}

/// 登录视图
struct LoginView: View {
    @StateObject private var auth = SupabaseService.shared
    @StateObject private var localization = LocalizationService.shared

    // 输入状态
    @State private var email: String = ""
    @State private var otp: String = ""
    @State private var currentStep: LoginStep = .email

    // UI 状态
    @State private var countdown: Int = 0
    @State private var isSendingOTP: Bool = false
    @State private var isVerifying: Bool = false
    @State private var showSuccessAnimation: Bool = false

    // 协议同意状态
    @State private var hasAgreedToTerms: Bool = false
    @State private var showPrivacyPolicy: Bool = false
    @State private var showTermsOfService: Bool = false

    // 焦点状态
    @FocusState private var focusedField: FocusField?

    // 定时器
    @State private var timer: Timer?

    // 内容区域高度（根据步骤动态调整）
    private var contentHeight: CGFloat {
        currentStep == .email ? 180 : 250
    }

    // 窗口总高度
    private var windowHeight: CGFloat {
        currentStep == .email ? 500 : 570
    }

    var body: some View {
        VStack(spacing: 0) {
            // 品牌区域
            brandSection

            // 表单区域（固定高度，避免跳动）
            formContainer

            Spacer()

            // 底部信息
            footerSection
        }
        .frame(width: 400, height: windowHeight)
        .background(
            ZStack {
                // 渐变背景
                LinearGradient(
                    colors: [
                        Color(NSColor.controlBackgroundColor),
                        Color(NSColor.windowBackgroundColor)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // 微妙的装饰
                VStack {
                    Spacer()
                    Circle()
                        .fill(Color.accentColor.opacity(0.03))
                        .frame(width: 300, height: 300)
                        .offset(y: 100)
                }
            }
        )
        .onAppear {
            focusedField = .email
        }
        .alert(L("common.ok"), isPresented: .init(
            get: { auth.errorMessage != nil },
            set: { if !$0 { auth.errorMessage = nil } }
        )) {
            Button(L("common.ok"), role: .cancel) {
                auth.errorMessage = nil
            }
        } message: {
            Text(auth.errorMessage ?? "")
        }
    }

    // MARK: - Brand Section

    private var brandSection: some View {
        VStack(spacing: 12) {
            // Logo - 使用透明背景的 logo 图片
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)

            // 标题
            Text(L("app.name"))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            // 副标题
            Text(L("app.subtitle"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.top, 48)
        .padding(.bottom, 32)
    }

    // MARK: - Form Container

    private var formContainer: some View {
        VStack(spacing: 0) {
            // 进度指示器
            progressIndicator

            // 表单内容（固定高度容器）
            ZStack {
                switch currentStep {
                case .email:
                    emailForm
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                case .otp:
                    otpForm
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .frame(height: contentHeight)
            .clipped()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentStep)
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            // Step 1
            stepIndicator(number: 1, title: L("login.step_email"), isActive: currentStep == .email, isCompleted: currentStep == .otp)

            // Connector
            Rectangle()
                .fill(currentStep == .otp ? Color.accentColor : Color.gray.opacity(0.3))
                .frame(width: 40, height: 2)
                .animation(.easeInOut(duration: 0.3), value: currentStep)

            // Step 2
            stepIndicator(number: 2, title: L("login.step_verify"), isActive: currentStep == .otp, isCompleted: false)
        }
        .padding(.bottom, 24)
    }

    private func stepIndicator(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive || isCompleted ? Color.accentColor : Color.gray.opacity(0.2))
                    .frame(width: 24, height: 24)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isActive ? .white : .secondary)
                }
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }

    // MARK: - Email Form

    private var emailForm: some View {
        VStack(spacing: 16) {
            // 邮箱输入框
            VStack(alignment: .leading, spacing: 8) {
                Text(L("login.email"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "envelope")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    TextField(L("login.email_placeholder"), text: $email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .onSubmit {
                            sendOTP()
                        }
                        .focused($focusedField, equals: .email)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedField == .email ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
            }

            // 发送按钮
            Button(action: sendOTP) {
                HStack(spacing: 8) {
                    if isSendingOTP {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                            .tint(.white)
                    } else {
                        Text(L("login.send_code"))
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(canSendEmail ? Color.accentColor : Color.gray.opacity(0.3))
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canSendEmail || isSendingOTP)
            .keyboardShortcut(.defaultAction)
            .animation(.easeInOut(duration: 0.2), value: canSendEmail)

            // 提示
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                Text(L("login.first_time_hint"))
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
        }
    }

    private var canSendEmail: Bool {
        !email.isEmpty && isValidEmail(email) && !isSendingOTP && hasAgreedToTerms
    }

    // MARK: - OTP Form

    private var otpForm: some View {
        VStack(spacing: 16) {
            // 已发送提示
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    Text(L("login.code_sent_to"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Text(email)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 4)

            // OTP 输入框
            VStack(alignment: .leading, spacing: 8) {
                Text(L("login.verification_code"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    TextField(L("login.code_placeholder"), text: $otp)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .onSubmit {
                            verifyOTP()
                        }
                        .focused($focusedField, equals: .otp)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedField == .otp ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                )
            }

            // 验证按钮
            Button(action: verifyOTP) {
                HStack(spacing: 8) {
                    if isVerifying {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                            .tint(.white)
                    } else {
                        Text(L("login.login"))
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(otp.count == 6 ? Color.accentColor : Color.gray.opacity(0.3))
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(otp.count != 6 || isVerifying || !hasAgreedToTerms)
            .keyboardShortcut(.defaultAction)
            .animation(.easeInOut(duration: 0.2), value: otp.count)

            // 重新发送
            HStack(spacing: 16) {
                if countdown > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("\(countdown)\(L("login.seconds"))")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                } else {
                    Button(action: resendOTP) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text(L("login.resend"))
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(isSendingOTP)
                }

                Button(action: goBackToEmail) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10))
                        Text(L("login.change_email"))
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 36)

            // 协议同意
            HStack(spacing: 4) {
                Button(action: { hasAgreedToTerms.toggle() }) {
                    Image(systemName: hasAgreedToTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(hasAgreedToTerms ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Text("我已阅读并同意")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Button(action: { showTermsOfService = true }) {
                    Text("用户协议")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Text("和")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Button(action: { showPrivacyPolicy = true }) {
                    Text("隐私政策")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 24)
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentSheet(
                title: "隐私政策",
                content: LegalDocuments.loadPrivacyPolicy()
            )
        }
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentSheet(
                title: "用户协议",
                content: LegalDocuments.loadTermsOfService()
            )
        }
    }

    // MARK: - Actions

    private func sendOTP() {
        guard isValidEmail(email) else { return }

        isSendingOTP = true

        Task {
            do {
                try await auth.sendOTP(email: email)
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        currentStep = .otp
                    }
                    startCountdown()
                    // 延迟聚焦，等待动画完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        focusedField = .otp
                    }
                }
            } catch {
                await MainActor.run {
                    auth.errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isSendingOTP = false
            }
        }
    }

    private func resendOTP() {
        countdown = 0
        timer?.invalidate()
        sendOTP()
    }

    private func goBackToEmail() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentStep = .email
            otp = ""
        }
        timer?.invalidate()
        countdown = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            focusedField = .email
        }
    }

    private func verifyOTP() {
        guard otp.count == 6 else { return }

        isVerifying = true

        Task {
            do {
                try await auth.verifyOTP(email: email, otp: otp)
                // 登录成功后会自动切换到主界面
            } catch {
                await MainActor.run {
                    auth.errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isVerifying = false
            }
        }
    }

    // MARK: - Helpers

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }

    private func startCountdown() {
        countdown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .frame(width: 400, height: 520)
    }
}
#endif
