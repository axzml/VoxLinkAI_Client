//
//  SupabaseService.swift
//  VoxLink
//
//  Supabase 认证服务
//  支持用户认证、会话管理、用户配置获取和实时配额同步
//

import AppKit
import Combine
import Foundation
import Supabase

/// 认证状态
enum AuthState {
    case notAuthenticated    // 未登录
    case authenticating      // 正在登录中
    case authenticated       // 已登录
    case error(String)       // 登录错误
}

/// 认证服务错误
enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case invalidEmail
    case invalidOTP
    case networkError(String)
    case serverError(String)
    case profileNotFound
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "请先登录"
        case .invalidEmail:
            return "邮箱格式不正确"
        case .invalidOTP:
            return "验证码不正确或已过期"
        case .networkError(let message):
            return "网络错误: \(message)"
        case .serverError(let message):
            return "服务器错误: \(message)"
        case .profileNotFound:
            return "用户配置未找到"
        case .unknown(let error):
            return "未知错误: \(error.localizedDescription)"
        }
    }
}

/// Supabase 认证服务
/// 负责用户登录、会话管理、用户配置获取
/// ⚠️ 重要：配额数据通过 Realtime 实时同步，客户端不主动写入
@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    // MARK: - Published Properties

    /// 认证状态
    @Published private(set) var authState: AuthState = .notAuthenticated

    /// 是否已认证
    @Published private(set) var isAuthenticated: Bool = false

    /// 当前用户邮箱
    @Published private(set) var userEmail: String?

    /// 用户配置
    @Published private(set) var userProfile: UserProfile?

    /// 当前 Supabase 用户
    @Published private(set) var currentUser: User?

    /// 错误信息
    @Published var errorMessage: String?

    /// 是否正在加载
    @Published var isLoading: Bool = false

    /// Realtime 连接状态
    @Published private(set) var isRealtimeConnected: Bool = false

    // MARK: - Supabase Client

    /// Supabase 客户端
    private var supabaseClient: SupabaseClient!

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    /// Realtime 频道 - 用于监听配额变更
    private var profileChannel: RealtimeChannelV2?

    /// Realtime 监听 Task（用于取消订阅）
    private var realtimeListenerTask: Task<Void, Never>?

    /// 轮询定时器（Realtime 失败时的备用方案）
    private var pollingTimer: Timer?

    /// 轮询间隔（秒）
    private let pollingInterval: TimeInterval = 30.0

    /// 当前用户 ID（用于轮询）
    private var currentUserId: UUID?

    // MARK: - Initialization

    private init() {
        // Mock 模式：跳过 Supabase 客户端初始化
        if SupabaseConfig.useMockData {
            print("[SupabaseService] Mock mode enabled, skipping Supabase initialization")
            // 在 mock 模式下，直接设置为已认证状态（BYOK 模式）
            // 用户需要自己提供 API Key
            setupMockUser()
            return
        }

        // 正常模式：初始化 Supabase 客户端
        guard SupabaseConfig.isConfigured else {
            print("[SupabaseService] Warning: Supabase not configured. Please set SUPABASE_URL and SUPABASE_ANON_KEY in Secrets.plist")
            return
        }

        do {
            supabaseClient = try SupabaseClient(
                supabaseURL: SupabaseConfig.supabaseURL,
                supabaseKey: SupabaseConfig.supabaseAnonKey,
                options: .init(
                    auth: .init(
                        // 使用新的 session 行为：立即发射本地存储的 session
                        // 消除 "Initial session emitted after attempting to refresh" 警告
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )
            print("[SupabaseService] Client initialized successfully")
        } catch {
            print("[SupabaseService] Failed to initialize client: \(error)")
            // 允许继续，但登录会失败
        }

        // 注意：restoreSession 由 AppDelegate 调用，这里不再重复调用
    }

    /// 设置 Mock 用户（BYOK 模式）
    private func setupMockUser() {
        // 创建一个 mock 用户配置（basic 级别，使用自己的 API Key）
        let mockProfile = UserProfile(
            id: UUID(),
            email: "local@voxlink.ai",
            userLevel: .basic,
            durationLimitSeconds: 0,  // basic 用户无限制
            durationUsedSeconds: 0,
            reportLimit: 0,
            reportUsed: 0,
            quotaResetDate: Date(),
            subscriptionExpiresAt: nil,
            createdAt: Date(),
            lastActiveAt: Date()
        )

        self.userProfile = mockProfile
        self.userEmail = mockProfile.email
        self.isAuthenticated = true
        self.authState = .authenticated

        print("[SupabaseService] Mock user setup complete - BYOK mode active")
    }

    // MARK: - Public Methods

    /// 发送验证码到邮箱
    /// - Parameter email: 用户邮箱
    /// - Returns: 是否发送成功
    func sendOTP(email: String) async throws {
        guard isValidEmail(email) else {
            throw AuthError.invalidEmail
        }

        guard supabaseClient != nil else {
            throw AuthError.serverError("Supabase 客户端未初始化，请检查配置")
        }

        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            // 使用 Supabase 发送 OTP
            try await supabaseClient.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "voxlinkai://auth-callback")
            )
            print("[SupabaseService] OTP sent to: \(email)")
        } catch {
            print("[SupabaseService] Failed to send OTP: \(error)")
            throw AuthError.networkError(error.localizedDescription)
        }
    }

    /// 验证验证码
    /// - Parameters:
    ///   - email: 用户邮箱
    ///   - otp: 验证码
    func verifyOTP(email: String, otp: String) async throws {
        guard isValidEmail(email) else {
            throw AuthError.invalidEmail
        }

        guard otp.count == 6 else {
            throw AuthError.invalidOTP
        }

        guard supabaseClient != nil else {
            throw AuthError.serverError("Supabase 客户端未初始化，请检查配置")
        }

        await MainActor.run {
            isLoading = true
            authState = .authenticating
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            // 使用 Supabase 验证 OTP
            let session = try await supabaseClient.auth.verifyOTP(
                email: email,
                token: otp,
                type: .email
            )

            let user = session.user
            let userId = user.id

            // 获取或创建用户配置
            let profile = await fetchProfile(userId: userId, email: email)

            await MainActor.run {
                self.currentUser = user
                self.userEmail = email
                self.userProfile = profile
                self.isAuthenticated = true
                self.authState = .authenticated
            }

            // 保存登录状态
            saveSession(email: email, userId: userId.uuidString)

            // 订阅配额变更（Realtime）
            await subscribeToProfileChanges(userId: userId)

            print("[SupabaseService] User authenticated: \(email)")
        } catch let error as AuthError {
            throw error
        } catch {
            print("[SupabaseService] Failed to verify OTP: \(error)")
            throw AuthError.invalidOTP
        }
    }

    /// 恢复会话
    func restoreSession() async {
        // Mock 模式：不需要恢复会话
        guard !SupabaseConfig.useMockData else {
            return
        }

        guard supabaseClient != nil else {
            await MainActor.run {
                self.authState = .notAuthenticated
                self.isAuthenticated = false
            }
            return
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            // 尝试从 Supabase 恢复会话
            let session = try await supabaseClient.auth.session
            let user = session.user
            let userId = user.id

            print("[SupabaseService] Found session for: \(user.email ?? "unknown")")

            // 获取或创建用户配置
            let profile = await fetchProfile(userId: userId, email: user.email ?? "")

            await MainActor.run {
                self.currentUser = user
                self.userEmail = user.email
                self.userProfile = profile
                self.isAuthenticated = true
                self.authState = .authenticated
                isLoading = false
            }

            // 保存登录状态
            saveSession(email: user.email ?? "", userId: userId.uuidString)

            // 订阅配额变更（Realtime）
            await subscribeToProfileChanges(userId: userId)

            print("[SupabaseService] Session restored successfully for: \(user.email ?? "")")
        } catch {
            print("[SupabaseService] No valid session to restore: \(error.localizedDescription)")
            await MainActor.run {
                self.authState = .notAuthenticated
                self.isAuthenticated = false
                isLoading = false
            }
        }
    }

    /// 获取 Dodo Payments 支付链接
    /// - Parameter productUrl: Dodo 后台提供的 Checkout URL
    /// - Parameter targetLevel: 目标等级 ("basic" 或 "pro")
    func getDodoCheckoutURL(baseCheckoutUrl: String, targetLevel: String) -> URL? {
        guard let userId = currentUser?.id else { return nil }

        var components = URLComponents(string: baseCheckoutUrl)

        // 添加 Metadata 确保后端能够识别用户和等级
        let metadataItems = [
            URLQueryItem(name: "metadata[user_id]", value: userId.uuidString.lowercased()),
            URLQueryItem(name: "metadata[user_level]", value: targetLevel)
        ]

        if components?.queryItems == nil {
            components?.queryItems = metadataItems
        } else {
            components?.queryItems?.append(contentsOf: metadataItems)
        }

        return components?.url
    }

    /// 刷新用户信息
    func refreshProfile() async {
        guard let user = currentUser, let email = user.email else { return }

        await MainActor.run {
            isLoading = true
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        let profile = await fetchProfile(userId: user.id, email: email)
        await MainActor.run {
            self.userProfile = profile
        }
        print("[SupabaseService] Profile refreshed")
    }

    /// 获取当前会话 Token
    func getAccessToken() async -> String? {
        guard supabaseClient != nil, currentUser != nil else { return nil }
        do {
            let session = try await supabaseClient.auth.session
            return session.accessToken
        } catch {
            print("[SupabaseService] Failed to get session token: \(error)")
            return nil
        }
    }

    /// 登出
    func signOut() async throws {
        await MainActor.run {
            isLoading = true
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        // 取消 Realtime 订阅
        await unsubscribeFromProfileChanges()

        // 使用 Supabase 登出（非 mock 模式）
        if !SupabaseConfig.useMockData && supabaseClient != nil {
            try? await supabaseClient.auth.signOut()
        }

        // 清除本地存储
        UserDefaults.standard.removeObject(forKey: Keys.userEmail)
        UserDefaults.standard.removeObject(forKey: Keys.userId)

        // Mock 模式：重新设置 mock 用户而不是清除认证
        if SupabaseConfig.useMockData {
            setupMockUser()
            print("[SupabaseService] Mock mode: user reset")
            return
        }

        await MainActor.run {
            self.currentUser = nil
            self.userEmail = nil
            self.userProfile = nil
            self.isAuthenticated = false
            self.authState = .notAuthenticated
            self.isRealtimeConnected = false
        }

        print("[SupabaseService] User signed out")
    }


    /// 更新录音时长使用量（仅本地 UI 状态）
    /// ⚠️ 注意：此方法只更新本地内存状态，不发送任何网络请求
    /// 真实的配额扣除由 Go 后端完成，并通过 Realtime 同步回来
    /// - Parameter durationSeconds: 录音时长（秒）
    func updateDurationUsage(durationSeconds: Int) {
        guard var profile = userProfile else { return }

        // Basic 用户使用自己的 Key，不更新配额
        guard profile.userLevel != .basic else { return }

        profile.durationUsedSeconds += durationSeconds
        self.userProfile = profile

        print("[SupabaseService] Local duration usage updated: +\(durationSeconds)s (UI only, awaiting Realtime sync)")
    }

    /// 更新报告使用量（仅本地 UI 状态）
    /// ⚠️ 注意：此方法只更新本地内存状态，不发送任何网络请求
    func updateReportUsage() {
        guard var profile = userProfile, profile.userLevel == .free else { return }

        profile.reportUsed += 1
        self.userProfile = profile

        print("[SupabaseService] Local report usage updated: \(profile.reportUsed)/\(profile.reportLimit) (UI only)")
    }

    /// 使用服务器返回的配额数据更新本地状态
    /// 这确保了本地状态与服务器完全一致
    func updateQuotaFromServer(durationUsed: Int, durationLimit: Int, reportUsed: Int, reportLimit: Int) {
        guard var profile = userProfile else { return }

        // 只更新可变字段（limits 是不可变的，由用户等级决定）
        profile.durationUsedSeconds = durationUsed
        profile.reportUsed = reportUsed

        self.userProfile = profile
        print("[SupabaseService] Quota synced from server: duration=\(durationUsed)/\(durationLimit), reports=\(reportUsed)/\(reportLimit)")
    }

    // MARK: - Realtime Methods

    /// 订阅用户配置变更（Realtime）
    /// 当 Go 后端扣除配额后，客户端会收到实时通知
    /// 如果 Realtime 失败，自动启用轮询备用方案
    /// - Parameter userId: 用户 ID
    private func subscribeToProfileChanges(userId: UUID) async {
        // 保存用户 ID 用于轮询
        self.currentUserId = userId

        guard supabaseClient != nil else {
            print("[SupabaseService] Realtime 订阅失败: client 未初始化，启用轮询")
            startPolling()
            return
        }

        // 先取消之前的订阅（如果有）
        await unsubscribeFromProfileChanges()

        let userIdString = userId.uuidString.lowercased()
        let channelName = "profile:\(userIdString)"

        // 创建频道
        let channel = supabaseClient.realtimeV2.channel(channelName)
        self.profileChannel = channel

        // 在 Task 中持续消费事件流
        realtimeListenerTask = Task { [weak self] in
            do {
                // 获取 postgres 变更流（带过滤条件，只监听当前用户）
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "user_profiles",
                    filter: "id=eq.\(userIdString)"
                )

                // 订阅频道
                await channel.subscribe()

                // 更新连接状态
                await MainActor.run {
                    self?.isRealtimeConnected = true
                    self?.stopPolling()
                }

                print("[SupabaseService] Realtime 订阅成功")

                // 持续迭代事件流
                for await change in changes {
                    if Task.isCancelled { break }

                    // 在主线程处理变更
                    await MainActor.run {
                        self?.handleRealtimeAction(action: change)
                    }
                }

            } catch {
                print("[SupabaseService] Realtime 错误: \(error.localizedDescription)")

                await MainActor.run {
                    self?.isRealtimeConnected = false
                    self?.startPolling()
                }
            }
        }
    }

    // MARK: - Polling Fallback

    /// 启动轮询（Realtime 失败时的备用方案）
    private func startPolling() {
        stopPolling()

        DispatchQueue.main.async {
            self.pollingTimer = Timer.scheduledTimer(withTimeInterval: self.pollingInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshProfile()
                }
            }
            print("[SupabaseService] 轮询已启动（间隔 \(self.pollingInterval)s）")
        }
    }

    /// 停止轮询
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// 处理 Realtime Action
    private func handleRealtimeAction(action: AnyAction) {
        switch action {
        case .insert(let insertAction):
            handleProfileRecordUpdate(insertAction.record)

        case .update(let updateAction):
            handleProfileRecordUpdate(updateAction.record)

        case .delete:
            // DELETE 事件通常不应发生
            break

        @unknown default:
            break
        }
    }

    /// 处理 Profile 记录更新
    private func handleProfileRecordUpdate(_ record: [String: Any]) {
        // 从 AnyJSON 中提取字符串值
        let idString = extractString(from: record["id"])
        let email = extractString(from: record["email"])
        let userLevelString = extractString(from: record["user_level"])

        guard let idString = idString,
              let uuid = UUID(uuidString: idString),
              let email = email,
              let userLevelString = userLevelString,
              let userLevel = UserLevel(rawValue: userLevelString) else {
            print("[SupabaseService] Realtime 数据解析失败")
            return
        }

        // 提取配额字段
        let durationLimitSeconds = extractInt(from: record["duration_limit_seconds"])
        let durationUsedSeconds = extractInt(from: record["duration_used_seconds"])
        let reportLimit = extractInt(from: record["report_limit"])
        let reportUsed = extractInt(from: record["report_used"])

        // 提取日期字段
        let quotaResetDate = parseDateFromAnyJSON(from: record["quota_reset_date"]) ?? Date()
        let subscriptionExpiresAt = parseDateFromAnyJSON(from: record["subscription_expires_at"])
        let createdAt = parseDateFromAnyJSON(from: record["created_at"]) ?? Date()
        let lastActiveAt = parseDateFromAnyJSON(from: record["last_active_at"]) ?? Date()

        // 创建并更新 UserProfile
        let newProfile = UserProfile(
            id: uuid,
            email: email,
            userLevel: userLevel,
            durationLimitSeconds: durationLimitSeconds,
            durationUsedSeconds: durationUsedSeconds,
            reportLimit: reportLimit,
            reportUsed: reportUsed,
            quotaResetDate: quotaResetDate,
            subscriptionExpiresAt: subscriptionExpiresAt,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt
        )

        self.userProfile = newProfile
        print("[SupabaseService] 配额同步: \(newProfile.durationUsedSeconds)/\(newProfile.durationLimitSeconds)s")
    }

    /// 从 AnyJSON 中提取字符串值
    private func extractString(from value: Any?) -> String? {
        guard let value = value else { return nil }

        // 尝试直接转换为 String
        if let stringValue = value as? String {
            return stringValue
        }

        // 对于 AnyJSON 类型，使用 description 并去除可能的引号
        let desc = String(describing: value)
        if desc == "<null>" || desc == "null" {
            return nil
        }
        return desc
    }

    /// 从 AnyJSON 中提取 Int 值
    private func extractInt(from value: Any?) -> Int {
        guard let value = value else { return 0 }

        if let intValue = value as? Int {
            return intValue
        } else if let doubleValue = value as? Double {
            return Int(doubleValue)
        } else if let stringValue = value as? String {
            return Int(stringValue) ?? 0
        }

        // 对于 AnyJSON 类型，尝试使用 description
        let desc = String(describing: value)
        return Int(desc) ?? 0
    }

    /// 从 AnyJSON 中解析日期
    private func parseDateFromAnyJSON(from value: Any?) -> Date? {
        guard let value = value else { return nil }

        // 检查是否为 null
        let desc = String(describing: value)
        if desc == "<null>" || desc == "null" {
            return nil
        }

        // 如果已经是 Date 类型
        if let date = value as? Date {
            return date
        }

        // 如果是 String 类型，使用 ISO8601 解析
        if let dateString = value as? String {
            return parseISO8601Date(from: dateString)
        }

        // 对于 AnyJSON，使用 description 作为日期字符串
        return parseISO8601Date(from: desc)
    }

    /// 解析 ISO8601 日期字符串
    private func parseISO8601Date(from dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        // 尝试不带毫秒的格式
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    /// 取消用户配置变更订阅
    private func unsubscribeFromProfileChanges() async {
        stopPolling()

        realtimeListenerTask?.cancel()
        realtimeListenerTask = nil

        guard let channel = profileChannel else { return }

        do {
            try await supabaseClient.removeChannel(channel)
        } catch {
            print("[SupabaseService] 取消订阅失败: \(error.localizedDescription)")
        }

        profileChannel = nil
        isRealtimeConnected = false
    }

    // MARK: - Private Methods

    /// 获取用户配置（只读）
    /// ⚠️ 客户端只能读取数据，不能修改
    /// Profile 由 Supabase 触发器在用户注册时自动创建
    private func fetchProfile(userId: UUID, email: String) async -> UserProfile {
        guard supabaseClient != nil else {
            return UserProfile(id: userId, email: email, userLevel: .free)
        }

        let userIdString = userId.uuidString.lowercased()

        do {
            let response = try await supabaseClient
                .from("user_profiles")
                .select()
                .eq("id", value: userIdString)
                .single()
                .execute()

            let supabaseResponse = try JSONDecoder().decode(SupabaseUserProfileResponse.self, from: response.data)

            if let profile = supabaseResponse.toUserProfile() {
                return profile
            }
        } catch {
            print("[SupabaseService] 获取用户配置失败: \(error.localizedDescription)")
        }

        // Fallback: 返回本地默认值
        print("[SupabaseService] 使用本地默认配置")
        return UserProfile(id: userId, email: email, userLevel: .free)
    }

    /// 验证邮箱格式
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }

    /// 保存会话到本地
    private func saveSession(email: String, userId: String) {
        UserDefaults.standard.set(email, forKey: Keys.userEmail)
        UserDefaults.standard.set(userId, forKey: Keys.userId)
    }

    /// 设置错误信息
    private func setError(_ message: String) {
        Task { @MainActor in
            self.errorMessage = message
            self.authState = .error(message)
        }
    }
}

// MARK: - Keys

private extension SupabaseService {
    enum Keys {
        static let userEmail = "voxlinkai_auth_email"
        static let userId = "voxlinkai_auth_user_id"
        static let sessionToken = "voxlinkai_session_token"
    }
}
