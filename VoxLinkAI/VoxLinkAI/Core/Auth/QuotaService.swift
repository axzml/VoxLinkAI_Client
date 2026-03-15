//
//  QuotaService.swift
//  VoxLink
//
//  配额检查服务 - BYOK 模式
//  所有功能免费，语音功能需用户自带阿里云 API Key
//
//  ⚠️ 安全说明：
//  此服务是纯粹的"配额缓存读取器"和"阈值拦截器"。
//  所有配额扣除由 Go 后端在 ASR 流程中完成，客户端不主动修改配额。
//

import Foundation
import Combine
import SwiftUI

/// 配额检查结果
enum QuotaCheckResult {
    case allowed
    case quotaExceeded(reason: String)
    case notLoggedIn
    case requiresAPIKey

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .allowed:
            return nil
        case .quotaExceeded(let reason):
            return reason
        case .notLoggedIn:
            return "请先登录"
        case .requiresAPIKey:
            return "请先配置阿里云 API Key"
        }
    }
}

/// 高级功能检查结果
enum AdvancedFeatureCheckResult {
    case allowed
    case notLoggedIn
    case requiresAPIKey

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .allowed:
            return nil
        case .notLoggedIn:
            return "请先登录"
        case .requiresAPIKey:
            return "请先配置阿里云 API Key"
        }
    }
}

/// 配额服务
/// 负责检查和管理用户配额
/// ⚠️ 重要：此服务不执行任何网络写入操作，只读取本地缓存进行前置拦截
class QuotaService: ObservableObject {
    static let shared = QuotaService()

    @Published private(set) var currentUsage: QuotaUsage?

    private let auth = SupabaseService.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // 监听用户配置变化
        auth.$userProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] profile in
                self?.updateCurrentUsage(profile: profile)
            }
            .store(in: &cancellables)
    }

    // MARK: - BYOK Mode Detection

    /// 检查是否处于 BYOK（自带 Key）模式
    private func isBYOKMode() -> Bool {
        if let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty {
            return true
        }
        return false
    }

    /// 检查 BYOK 模式是否可用（Key 已输入且已验证）
    private func checkBYOKModeValidity() -> (isValid: Bool, errorMessage: String?) {
        guard let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty else {
            return (false, nil)
        }

        if !SettingsStore.shared.isAliyunKeyValid {
            return (false, "您的 API Key 尚未验证，请前往设置中测试连通性")
        }

        return (true, nil)
    }

    // MARK: - Public Methods

    /// 检查是否可以开始录音
    func canStartRecording() -> QuotaCheckResult {
        guard auth.userProfile != nil else {
            return .notLoggedIn
        }

        // 检查是否配置了 API Key
        guard let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty else {
            return .requiresAPIKey
        }

        // Key 已输入，检查是否已验证
        let (isValid, errorMessage) = checkBYOKModeValidity()
        if !isValid {
            return .quotaExceeded(reason: errorMessage ?? "您的 API Key 尚未验证，请前往设置中测试连通性")
        }

        return .allowed
    }

    /// 检查是否可以使用基础功能（ASR + AI 润色）
    func canUseBasicFeature() -> QuotaCheckResult {
        guard auth.userProfile != nil else {
            return .notLoggedIn
        }

        if APIKeyStore.shared.aliyunASRAPIKey == nil || APIKeyStore.shared.aliyunASRAPIKey?.isEmpty == true {
            return .requiresAPIKey
        }
        return .allowed
    }

    /// 检查是否可以生成报告
    func canGenerateReport() -> QuotaCheckResult {
        guard auth.userProfile != nil else {
            return .notLoggedIn
        }
        return .allowed
    }

    /// 获取剩余录音时长（秒）
    func getRemainingDuration() -> Int {
        guard auth.userProfile != nil else { return 0 }
        return Int.max  // BYOK 模式无限制
    }

    /// 获取剩余报告次数
    func getRemainingReportCount() -> Int {
        guard auth.userProfile != nil else { return 0 }
        return Int.max
    }

    // MARK: - 本地配额更新（仅用于 UI 临时展示）

    /// 更新本地配额状态（乐观更新 UI）
    /// BYOK 模式下不更新配额
    func updateLocalDurationUsage(durationSeconds: Int) {
        guard auth.userProfile != nil else { return }

        // BYOK 模式：使用自己的 Key，不更新配额
        print("[QuotaService] BYOK mode - skipping local quota update")
    }

    /// 更新本地报告使用量（乐观更新 UI）
    func updateLocalReportUsage() {
        // BYOK 模式下不限制报告次数
    }

    // MARK: - 配额状态查询

    /// 获取配额状态文本
    func getQuotaStatusText() -> String {
        guard auth.userProfile != nil else {
            return "未登录"
        }

        if isBYOKMode() {
            return "BYOK 模式 - 无限制"
        }
        return "未配置 API Key"
    }

    /// 获取配额警告信息
    func getQuotaWarning() -> String? {
        guard auth.userProfile != nil else { return nil }

        if !isBYOKMode() {
            return "请配置阿里云 API Key 以使用语音功能"
        }

        return nil
    }

    // MARK: - Private Methods

    private func updateCurrentUsage(profile: UserProfile?) {
        guard let profile = profile else {
            currentUsage = nil
            return
        }

        currentUsage = QuotaUsage(
            durationUsedSeconds: profile.durationUsedSeconds,
            durationLimitSeconds: profile.durationLimitSeconds,
            reportUsed: profile.reportUsed,
            reportLimit: profile.reportLimit,
            userLevel: profile.userLevel
        )
    }
}

/// 配额使用情况
struct QuotaUsage {
    let durationUsedSeconds: Int
    let durationLimitSeconds: Int
    let reportUsed: Int
    let reportLimit: Int
    let userLevel: UserLevel

    var durationRemainingSeconds: Int {
        max(0, durationLimitSeconds - durationUsedSeconds)
    }

    var reportRemaining: Int {
        max(0, reportLimit - reportUsed)
    }

    var durationRemainingText: String {
        return "无限制"
    }

    var usagePercentage: Int {
        guard durationLimitSeconds > 0 else { return 0 }
        return min(100, (durationUsedSeconds * 100) / durationLimitSeconds)
    }

    /// 当前服务模式文本（用于 UI 展示）
    var currentModeText: String {
        if let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty {
            if SettingsStore.shared.isAliyunKeyValid {
                return "🚀 自带密钥 (BYOK)"
            } else {
                return "⚠️ Key 待验证"
            }
        }
        return "🔑 未配置 Key"
    }

    /// 当前服务模式颜色（用于 UI Badge）
    var currentModeColor: Color {
        if let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty {
            if SettingsStore.shared.isAliyunKeyValid {
                return .green
            } else {
                return .orange
            }
        }
        return .orange
    }
}