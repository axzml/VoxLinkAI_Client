//
//  UserProfile.swift
//  VoxLink
//
//  用户配置模型 - BYOK 模式（所有功能免费，语音功能需自带 API Key）
//

import Foundation

// MARK: - 用户等级

enum UserLevel: String, Codable, CaseIterable {
    case free = "free"       // 免费用户
    case basic = "basic"     // 自带 API Key 的用户
    case pro = "pro"         // 保留（Supabase 兼容）

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .basic: return "Basic"
        case .pro: return "Pro"
        }
    }

    var description: String {
        switch self {
        case .free: return "免费用户，配置阿里云 API Key 可使用语音功能"
        case .basic: return "自带阿里云 API Key，全功能解锁"
        case .pro: return "自带阿里云 API Key，全功能解锁"
        }
    }

    /// 是否需要自备 API Key（所有用户均需要）
    var requiresOwnAPIKey: Bool {
        return true
    }
}

// MARK: - 用户配置

struct UserProfile: Codable, Identifiable {
    let id: UUID
    let email: String
    let userLevel: UserLevel

    // MARK: - 录音时长配额

    /// 录音时长限制（秒）— BYOK 模式下不使用服务端配额
    let durationLimitSeconds: Int

    /// 已使用的录音时长（秒）
    var durationUsedSeconds: Int

    // MARK: - 报告配额

    /// 报告次数限制
    let reportLimit: Int

    /// 已使用的报告次数
    var reportUsed: Int

    // MARK: - 月度重置

    /// 配额重置日期
    var quotaResetDate: Date

    // MARK: - 订阅管理

    /// 订阅到期时间
    var subscriptionExpiresAt: Date?

    /// 订阅是否已过期
    var isSubscriptionExpired: Bool {
        guard let expiresAt = subscriptionExpiresAt else {
            return false
        }
        return Date() > expiresAt
    }

    /// 订阅剩余天数（用于 UI 显示）
    var subscriptionRemainingDays: Int? {
        guard let expiresAt = subscriptionExpiresAt else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expiresAt)
        return max(0, components.day ?? 0)
    }

    /// 订阅状态描述
    var subscriptionStatusText: String {
        return "免费"
    }

    // MARK: - 时间戳

    let createdAt: Date
    var lastActiveAt: Date

    // MARK: - 计算属性

    /// 录音时长是否已用完（BYOK 模式下始终为 false）
    var isDurationExhausted: Bool {
        return false
    }

    /// 报告次数是否已用完（BYOK 模式下始终为 false）
    var isReportExhausted: Bool {
        return false
    }

    /// 试用额度是否全部用完（BYOK 模式下始终为 false）
    var isTrialCompletelyUsed: Bool {
        return false
    }

    /// 剩余录音时长（秒）
    var remainingDurationSeconds: Int {
        return max(0, durationLimitSeconds - durationUsedSeconds)
    }

    /// 剩余报告次数
    var remainingReportCount: Int {
        return Int.max
    }

    /// 是否可以开始录音（BYOK 模式下始终为 true）
    func canStartRecording() -> Bool {
        return true
    }

    /// 剩余时长的格式化字符串
    var remainingDurationText: String {
        return "无限制"
    }

    /// 已使用时长的格式化字符串
    var usedDurationText: String {
        let totalSeconds = durationUsedSeconds
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else if minutes > 0 {
            return "\(minutes)min"
        } else {
            return "\(totalSeconds)s"
        }
    }

    /// 配额使用百分比
    var usagePercentage: Int {
        guard durationLimitSeconds > 0 else { return 0 }
        return min(100, (durationUsedSeconds * 100) / durationLimitSeconds)
    }

    // MARK: - 初始化器

    init(
        id: UUID,
        email: String,
        userLevel: UserLevel,
        durationLimitSeconds: Int? = nil,
        durationUsedSeconds: Int = 0,
        reportLimit: Int? = nil,
        reportUsed: Int = 0,
        quotaResetDate: Date = Date(),
        subscriptionExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.userLevel = userLevel
        self.durationLimitSeconds = durationLimitSeconds ?? 0
        self.reportLimit = reportLimit ?? 0
        self.durationUsedSeconds = durationUsedSeconds
        self.reportUsed = reportUsed
        self.quotaResetDate = quotaResetDate
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }
}

// MARK: - CodingKeys

extension UserProfile {
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userLevel = "user_level"
        case durationLimitSeconds = "duration_limit_seconds"
        case durationUsedSeconds = "duration_used_seconds"
        case reportLimit = "report_limit"
        case reportUsed = "report_used"
        case quotaResetDate = "quota_reset_date"
        case subscriptionExpiresAt = "subscription_expires_at"
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
    }
}

// MARK: - Supabase Response Models

/// Supabase 用户配置响应（从数据库查询）
struct SupabaseUserProfileResponse: Codable {
    let id: String
    let email: String
    let userLevel: String
    let durationLimitSeconds: Int?
    let durationUsedSeconds: Int?
    let reportLimit: Int?
    let reportUsed: Int?
    let quotaResetDate: String?
    let subscriptionExpiresAt: String?
    let createdAt: String?
    let lastActiveAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case userLevel = "user_level"
        case durationLimitSeconds = "duration_limit_seconds"
        case durationUsedSeconds = "duration_used_seconds"
        case reportLimit = "report_limit"
        case reportUsed = "report_used"
        case quotaResetDate = "quota_reset_date"
        case subscriptionExpiresAt = "subscription_expires_at"
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
    }

    /// 转换为 UserProfile
    func toUserProfile() -> UserProfile? {
        guard let uuid = UUID(uuidString: id),
              let level = UserLevel(rawValue: userLevel) else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return UserProfile(
            id: uuid,
            email: email,
            userLevel: level,
            durationLimitSeconds: durationLimitSeconds,
            durationUsedSeconds: durationUsedSeconds ?? 0,
            reportLimit: reportLimit,
            reportUsed: reportUsed ?? 0,
            quotaResetDate: quotaResetDate.flatMap { dateFormatter.date(from: $0) } ?? Date(),
            subscriptionExpiresAt: subscriptionExpiresAt.flatMap { dateFormatter.date(from: $0) },
            createdAt: createdAt.flatMap { dateFormatter.date(from: $0) } ?? Date(),
            lastActiveAt: lastActiveAt.flatMap { dateFormatter.date(from: $0) } ?? Date()
        )
    }
}
