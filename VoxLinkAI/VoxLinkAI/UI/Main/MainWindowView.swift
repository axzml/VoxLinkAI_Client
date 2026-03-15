//
//  MainWindowView.swift
//  VoxLink
//
//  主窗口视图 - Notion 风格侧边栏布局
//

import Supabase
import SwiftUI

// MARK: - Navigation Item

enum NavItem: String, CaseIterable {
    case dashboard = "首页"
    case longRecording = "持续录音"
    case history = "历史记录"
    case favorites = "收藏"

    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .longRecording: return "waveform"
        case .history: return "clock.arrow.circlepath"
        case .favorites: return "star"
        }
    }
}

// MARK: - Main Window View

struct MainWindowView: View {
    @StateObject private var historyStore = HistoryStore.shared
    @StateObject private var updateService = UpdateService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @State private var selectedNav: NavItem = .dashboard
    @State private var navigateToHistoryItemId: Int64?
    @State private var showUserMenu = false

    var body: some View {
        HStack(spacing: 0) {
            // 侧边栏
            sidebarView
                .frame(width: 200)
                .background(Color(nsColor: .controlBackgroundColor))

            // 分隔线
            Divider()

            // 主内容区
            mainContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToLongRecording)) { _ in
            selectedNav = .longRecording
        }
        .alert("发现新版本", isPresented: $updateService.showUpdateAlert) {
            Button("下载更新") {
                updateService.openDownloadPage()
            }
            Button("稍后提醒") {
                // Dismiss
            }
        } message: {
            Text("VoxLink AI \(updateService.latestVersion ?? "新版本") 已发布，建议更新以获得最佳体验。")
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Logo 区域
            logoSection
                .padding(.top, 20)
                .padding(.bottom, 24)

            // 导航项目
            navItemsSection

            Spacer()

            // 账号栏
            accountBar
                .padding(.bottom, 16)
        }
    }

    private var logoSection: some View {
        HStack(spacing: 10) {
            // Logo 图标 - 使用 App 图标
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
            }

            Text("VoxLink AI")
                .font(.system(size: 20, weight: .semibold))
        }
    }

    private var navItemsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(NavItem.allCases, id: \.self) { item in
                NavButton(
                    icon: item.icon,
                    title: item.rawValue,
                    isSelected: selectedNav == item
                ) {
                    selectedNav = item
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var accountBar: some View {
        VStack(spacing: 0) {
            // 配额状态栏（所有用户显示，包括 Mock/Basic 用户显示 BYOK 模式）
            if let profile = SupabaseService.shared.userProfile {
                QuotaStatusBar(profile: profile)
            }

            AccountBarView(
                userEmail: SupabaseService.shared.userEmail,
                userId: SupabaseService.shared.currentUser?.id.uuidString,
                avatarUrl: nil,
                onMenuToggle: { showUserMenu = true }
            )
            .popover(isPresented: $showUserMenu, arrowEdge: .leading) {
                UserMenuView(
                    userEmail: SupabaseService.shared.userEmail,
                    userId: SupabaseService.shared.currentUser?.id.uuidString,
                    avatarUrl: nil,
                    onAccountInfo: {
                        showUserMenu = false
                        AccountInfoWindowManager.shared.show()
                    },
                    onSettings: {
                        showUserMenu = false
                        SettingsWindowManager.shared.show()
                    },
                    onWebsite: {
                        showUserMenu = false
                        let baseURL = SupabaseConfig.websiteBaseURL
                        if !baseURL.isEmpty, let url = URL(string: baseURL) {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    onCheckUpdate: {
                        Task {
                            await UpdateService.shared.checkForUpdates()
                        }
                    },
                    onFeedback: {
                        showUserMenu = false
                        FeedbackWindowManager.shared.show()
                    },
                    onAbout: {
                        showUserMenu = false
                        AboutWindowManager.shared.show()
                    },
                    onLogout: {
                        showUserMenu = false
                        Task {
                            do {
                                try await SupabaseService.shared.signOut()
                                // Close main window and show login
                                MainWindowManager.shared.close()
                                LoginWindowManager.shared.show()
                            } catch {
                                print("[MainWindowView] Logout failed: \(error)")
                            }
                        }
                    }
                )
                .frame(width: 220)
                .padding(8)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContentView: some View {
        switch selectedNav {
        case .dashboard:
            DashboardView(
                onNavigateToLongRecording: {
                    selectedNav = .longRecording
                },
                onNavigateToHistory: { itemId in
                    // 先切换到历史记录页面，然后选中指定条目
                    navigateToHistoryItemId = itemId
                    selectedNav = .history
                }
            )
        case .longRecording:
            LongRecordingView()
        case .history:
            HistoryTabView(initialSelectedItemId: navigateToHistoryItemId)
                .onAppear {
                    // 清空，避免重复选中
                    navigateToHistoryItemId = nil
                }
        case .favorites:
            FavoritesView()
        }
    }
}

// MARK: - Nav Button

struct NavButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 14))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .primary)
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @StateObject private var historyStore = HistoryStore.shared
    @State private var isRecentRecordsVisible: Bool = true

    /// 导航到长时录音页面的回调
    var onNavigateToLongRecording: (() -> Void)?
    /// 导航到历史记录页面并选中指定条目的回调
    var onNavigateToHistory: ((Int64) -> Void)?

    /// 获取 ASR 服务（通过 AppServices 单例）
    private var asrService: ASRService {
        AppServices.shared.asrService
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 标题
                Text("首页")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, 8)

                // 功能区 + 统计区（并排，2×2 布局）
                HStack(alignment: .top, spacing: 20) {
                    // 左侧：功能区
                    functionAreaView

                    // 右侧：统计区
                    statsAreaView
                }

                // 最近记录
                recentRecordsView
            }
            .padding(24)
        }
    }

    // MARK: - Function Area (上下堆叠)

    private var functionAreaView: some View {
        VStack(spacing: 12) {
            // 短时录音
            FunctionCard(
                icon: "mic.fill",
                title: "短时录音",
                subtitle: "按住 Option 或点击该图标",
                color: .blue
            ) {
                startShortRecording()
            }

            // 持续录音
            FunctionCard(
                icon: "waveform",
                title: "持续录音",
                subtitle: "支持超长时间录音，智能人声检测",
                color: .green
            ) {
                onNavigateToLongRecording?()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    // MARK: - Stats Area (2×2) - 横向布局

    private var statsAreaView: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                // 今日转录 - 统计图标
                StatCard(
                    icon: "chart.bar.fill",
                    title: "今日转录",
                    value: "\(todayCount)",
                    color: .cyan
                )

                // 本周转录
                StatCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "本周转录",
                    value: "\(weekCount)",
                    color: .green
                )

                // 总字数
                StatCard(
                    icon: "doc.text.fill",
                    title: "总字数",
                    value: totalChars,
                    color: .orange
                )

                // 历史条数
                StatCard(
                    icon: "archivebox.fill",
                    title: "历史条数",
                    value: "\(historyStore.items.count)",
                    color: .purple
                )
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    /// 开始短时录音
    private func startShortRecording() {
        Task { @MainActor in
            print("[Dashboard] 短时录音按钮点击")
            await asrService.startRecording()
        }
    }

    // MARK: - Recent Records

    private var recentRecordsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题行 + 可见性切换
            HStack(spacing: 8) {
                Text("最近记录")
                    .font(.system(size: 18, weight: .semibold))

                Button(action: {
                    isRecentRecordsVisible.toggle()
                }) {
                    Image(systemName: isRecentRecordsVisible ? "eye" : "eye.slash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isRecentRecordsVisible ? "隐藏记录" : "显示记录")

                Spacer()
            }

            if historyStore.items.isEmpty {
                emptyStateView
            } else {
                ForEach(historyStore.items.prefix(7)) { item in
                    RecentRecordRow(
                        item: item,
                        isVisible: isRecentRecordsVisible,
                        onTap: {
                            onNavigateToHistory?(item.id)
                        }
                    )
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("暂无转录记录")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("点击上方按钮或按住 Option 键开始语音输入")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Statistics

    private var todayCount: Int {
        let calendar = Calendar.current
        return historyStore.items.filter { calendar.isDateInToday($0.createdAt) }.count
    }

    private var weekCount: Int {
        let calendar = Calendar.current
        let now = Date()
        return historyStore.items.filter {
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear)
        }.count
    }

    private var totalChars: String {
        let total = historyStore.items.reduce(0) { $0 + ($1.polished ?? $1.text).count }
        if total >= 10000 {
            return String(format: "%.1fk", Double(total) / 1000)
        }
        return "\(total)"
    }
}

// MARK: - Dashboard Card (功能区 - 纵向布局)

struct DashboardCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isButton: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isButton {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .cornerRadius(12)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .contentShape(Rectangle())
    }
}

// MARK: - Function Card (功能区 - 上下堆叠)

struct FunctionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 左侧：图标
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.15))
                    .cornerRadius(10)

                // 右侧：标题和副标题
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // 右侧箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(.regularMaterial)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card (统计区 - 横向布局)

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            // 左侧：图标
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15))
                .cornerRadius(10)

            // 右侧：标题和数值
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Recent Record Row

struct RecentRecordRow: View {
    let item: HistoryItem
    var isVisible: Bool = true
    var onTap: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isVisible ? previewText : maskedText)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .foregroundColor(isVisible ? .primary : .secondary)

                Text(timeString)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if item.polished != nil {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }

            // 箭头指示器（可点击跳转）
            Button(action: {
                onTap?()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("点击查看详情")
            .onHover { hovering in
                isHovered = hovering
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private var previewText: String {
        let text = item.polished ?? item.text
        return text.count <= 50 ? text : String(text.prefix(50)) + "..."
    }

    private var maskedText: String {
        // 生成与原文长度相同的遮罩字符
        let length = min(previewText.count, 50)
        return String(repeating: "•", count: length)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: item.createdAt)
    }
}

// MARK: - History Tab View

struct HistoryTabView: View {
    var initialSelectedItemId: Int64?

    var body: some View {
        HistoryView(initialSelectedItemId: initialSelectedItemId)
            .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Unified Favorite Item

/// 统一的收藏项类型
enum FavoriteItem: Identifiable, Equatable {
    case shortRecording(HistoryItem)
    case longRecording(LongRecordingSession)

    var id: String {
        switch self {
        case .shortRecording(let item):
            return "short_\(item.id)"
        case .longRecording(let session):
            return "long_\(session.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .shortRecording(let item):
            return item.createdAt
        case .longRecording(let session):
            return session.startTime
        }
    }

    var title: String {
        switch self {
        case .shortRecording(let item):
            return item.polished ?? item.text
        case .longRecording(let session):
            return session.displayTitle
        }
    }

    var isPolished: Bool {
        switch self {
        case .shortRecording(let item):
            return item.polished != nil
        case .longRecording:
            return false  // 长录音在时间轴中显示润色状态
        }
    }

    static func == (lhs: FavoriteItem, rhs: FavoriteItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Favorites View

struct FavoritesView: View {
    @StateObject private var historyStore = HistoryStore.shared
    @ObservedObject private var longRecordingStore = LongRecordingStore.shared
    @State private var selectedItem: FavoriteItem?
    @State private var selectedLongSession: LongRecordingSession?

    private var allFavorites: [FavoriteItem] {
        var items: [FavoriteItem] = []

        // 添加短时录音收藏
        for item in historyStore.getFavorites() {
            items.append(.shortRecording(item))
        }

        // 添加持续录音收藏
        for session in longRecordingStore.getFavoriteSessions() {
            items.append(.longRecording(session))
        }

        // 按时间排序（最新的在前）
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if allFavorites.isEmpty {
                // 空状态：居中显示一个空状态视图
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                // 有内容：左右分栏布局
                HStack(spacing: 0) {
                    // 左侧：收藏列表
                    favoritesListView
                        .frame(width: 320)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

                    Divider()

                    // 右侧：详情视图
                    detailView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: selectedItem) { oldValue, newValue in
            // 当选中持续录音时，加载其思维段
            if case .longRecording(let session) = newValue {
                selectedLongSession = session
                longRecordingStore.loadThoughtSegments(for: session.id)
            } else {
                selectedLongSession = nil
            }
        }
    }

    // MARK: - Left: Favorites List

    private var favoritesListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                Text("收藏")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(allFavorites.count) 条记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(allFavorites) { item in
                        UnifiedFavoriteRow(
                            item: item,
                            isSelected: selectedItem?.id == item.id
                        ) {
                            selectedItem = item
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("暂无收藏记录")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("在语音记录中点击收藏按钮\n将常用内容添加到这里")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Right: Detail View

    @ViewBuilder
    private var detailView: some View {
        if let item = selectedItem {
            switch item {
            case .shortRecording(let historyItem):
                shortRecordingDetailView(historyItem)
            case .longRecording(let session):
                longRecordingDetailView(session)
            }
        } else {
            emptyDetailView
        }
    }

    private func shortRecordingDetailView(_ item: HistoryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题栏
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("短时录音")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(dateString(from: item.createdAt))
                            .font(.headline)
                    }
                    Spacer()
                    // 操作按钮
                    HStack(spacing: 12) {
                        Button(action: {
                            copyText(item.polished ?? item.text)
                        }) {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            historyStore.toggleFavorite(id: item.id)
                        }) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                        }
                        .buttonStyle(.bordered)
                        .help("取消收藏")
                    }
                }

                Divider()

                // 内容
                VStack(alignment: .leading, spacing: 12) {
                    if item.polished != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.blue)
                            Text("润色后")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        Text(item.polished ?? "")
                            .font(.body)
                            .textSelection(.enabled)

                        Divider()

                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                            Text("原文")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(item.text)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text(item.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func longRecordingDetailView(_ session: LongRecordingSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("持续录音")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(session.displayTitle)
                        .font(.headline)
                }

                Spacer()

                Text(session.durationString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                // 操作按钮
                Button(action: {
                    LongRecordingStore.shared.toggleFavorite(session.id)
                }) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
                .buttonStyle(.bordered)
                .help("取消收藏")
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // 时间轴
            ScrollView {
                VStack(spacing: 0) {
                    if longRecordingStore.currentThoughtSegments.isEmpty {
                        Text("暂无内容")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else {
                        TimelineContainer {
                            ForEach(Array(longRecordingStore.currentThoughtSegments.enumerated()), id: \.element.id) { index, segment in
                                TimelineSegmentRow(
                                    segment: segment,
                                    isLeft: segment.isOnLeft,
                                    isLast: index == longRecordingStore.currentThoughtSegments.count - 1,
                                    sessionStartTime: session.startTime
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))

            Text("选择一个收藏项查看详情")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Helpers

    private func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Unified Favorite Row

struct UnifiedFavoriteRow: View {
    let item: FavoriteItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 类型图标
                Image(systemName: typeIcon)
                    .font(.system(size: 14))
                    .foregroundColor(typeColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        // 类型标签
                        Text(typeLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(typeColor)
                            .cornerRadius(4)

                        Text(dateString)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if item.isPolished {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    }
                }

                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var typeIcon: String {
        switch item {
        case .shortRecording:
            return "mic.fill"
        case .longRecording:
            return "waveform"
        }
    }

    private var typeColor: Color {
        switch item {
        case .shortRecording:
            return .blue
        case .longRecording:
            return .green
        }
    }

    private var typeLabel: String {
        switch item {
        case .shortRecording:
            return "短时"
        case .longRecording:
            return "持续"
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: item.createdAt)
    }
}

// MARK: - Long Recording View

struct LongRecordingView: View {
    @ObservedObject private var store = LongRecordingStore.shared
    @ObservedObject private var service = LongRecordingService.shared
    @State private var isIntroCollapsed = false
    @State private var selectedSession: LongRecordingSession?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isEditMode = false
    @State private var selectedSessionIds: Set<Int64> = []
    @State private var showBatchDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // 可折叠介绍区（始终显示）
            introSection

            // 主内容区：左侧控制+历史 | 右侧时光轴
            HStack(spacing: 0) {
                // 左侧 1/3
                VStack(spacing: 0) {
                    // 录音控制区
                    recordingControlSection

                    Divider()

                    // 历史展示区
                    historySection
                }
                .frame(width: 280)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

                Divider()

                // 右侧 2/3 时光轴
                timelineSection
            }
        }
        .alert("录音错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .onAppear {
            store.loadSessions()
        }
        .onDisappear {
            // 当用户离开持续录音页面时，如果不是正在录音，清空时光轴状态
            // 这样用户下次进入时会看到初始状态，而不是之前的结果
            if service.state == .idle {
                store.clearCurrentViewingState()
            }
        }
    }

    // MARK: - Intro Section

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isIntroCollapsed {
                // 折叠状态：显示简要提示和展开按钮
                HStack {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundColor(.green)

                    Text("持续录音：智能人声检测，自动裁剪静音")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: { withAnimation { isIntroCollapsed = false } }) {
                        HStack(spacing: 4) {
                            Text("展开")
                                .font(.system(size: 11))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                // 展开状态：显示完整介绍
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("智能化检测人声，有效减少无效录音，克服长时间录音中的关键难点。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { withAnimation { isIntroCollapsed = true } }) {
                            HStack(spacing: 4) {
                                Text("收起")
                                    .font(.system(size: 11))
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 16) {
                        advantageChip(icon: "brain.head.profile", text: "智能人声检测")
                        advantageChip(icon: "scissors", text: "自动裁剪静音")
                        advantageChip(icon: "clock.arrow.circlepath", text: "时光轴记录")
                        advantageChip(icon: "bolt.fill", text: "低功耗运行")
                    }
                }
                .padding(16)
            }
        }
        .background(.ultraThinMaterial)
    }

    private func advantageChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.green)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Recording Control Section

    private var recordingControlSection: some View {
        VStack(spacing: 12) {
            // 状态显示
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(service.state.displayName)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text(durationString)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            // 控制按钮
            HStack(spacing: 12) {
                // 开始/暂停按钮
                Button(action: {
                    // 在 Task 外捕获当前状态，避免状态竞争
                    let currentState = service.state
                    print("[LongRecordingView] Button clicked, state: \(currentState)")
                    Task {
                        print("[LongRecordingView] Task started")
                        if currentState == .idle {
                            // 检查前置条件
                            print("[LongRecordingView] Checking prerequisites...")
                            if !checkPrerequisites() {
                                print("[LongRecordingView] Prerequisites check failed")
                                return
                            }
                            // 开始新录音前，清空当前选中的历史记录
                            // 这样时光轴会显示新录音的内容，而不是之前查看的历史记录
                            selectedSession = nil
                            print("[LongRecordingView] Calling startRecording...")
                            await service.startRecording()
                            print("[LongRecordingView] startRecording returned")
                        } else if currentState == .recording {
                            await service.pauseRecording()
                        } else if currentState == .paused {
                            await service.resumeRecording()
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: controlButtonIcon)
                            .font(.system(size: 14))
                        Text(controlButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(controlButtonColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 停止按钮
                if service.state == .recording || service.state == .paused {
                    Button(action: {
                        print("[LongRecordingView] Stop button clicked")
                        Task {
                            await service.stopRecording()
                        }
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14))
                            .frame(width: 44, height: 38)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    /// 检查录音前置条件
    private func checkPrerequisites() -> Bool {
        print("[LongRecordingView] checkPrerequisites called")

        // 检查凭证（针对 Basic 用户需要检查 API Key，Free/Pro 可以使用 STS）
        let profile = SupabaseService.shared.userProfile
        if profile?.userLevel.requiresOwnAPIKey == true {
            guard let apiKey = APIKeyStore.shared.aliyunASRAPIKey, !apiKey.isEmpty else {
                print("[LongRecordingView] API Key not configured for Basic user")
                errorMessage = "请先在设置中配置阿里云 API Key"
                showError = true
                return false
            }
        } else if profile == nil && (!SettingsStore.shared.aliyunAPIKey.isEmpty) {
            // 未登录但有本地 Key，允许
        } else if profile == nil {
            // 未登录且无本地 Key
            errorMessage = "请先登录或配置阿里云 API Key"
            showError = true
            return false
        }

        print("[LongRecordingView] Prerequisites check passed")
        return true
    }

    private var statusColor: Color {
        switch service.state {
        case .idle: return .gray
        case .recording: return .green
        case .paused: return .orange
        case .processing: return .blue
        }
    }

    private var controlButtonIcon: String {
        switch service.state {
        case .idle: return "play.fill"
        case .recording: return "pause.fill"
        case .paused: return "play.fill"
        case .processing: return "hourglass"
        }
    }

    private var controlButtonTitle: String {
        switch service.state {
        case .idle: return "开始录音"
        case .recording: return "暂停"
        case .paused: return "继续"
        case .processing: return "处理中"
        }
    }

    private var controlButtonColor: Color {
        switch service.state {
        case .idle: return .green
        case .recording: return .orange
        case .paused: return .green
        case .processing: return .gray
        }
    }

    private var durationString: String {
        let hours = Int(service.recordingDuration) / 3600
        let minutes = Int(service.recordingDuration) % 3600 / 60
        let seconds = Int(service.recordingDuration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(spacing: 0) {
            // 编辑模式工具栏
            if isEditMode {
                editModeToolbar
            } else {
                // 普通模式标题栏
                HStack {
                    Text("历史记录")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if !store.sessions.isEmpty {
                        Button("编辑") {
                            withAnimation {
                                isEditMode = true
                                selectedSessionIds.removeAll()
                            }
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // 历史记录列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: selectedSession?.id == session.id,
                            thoughtSegmentCount: store.getThoughtSegmentCount(for: session.id),
                            isEditMode: isEditMode,
                            isChecked: selectedSessionIds.contains(session.id)
                        ) {
                            if isEditMode {
                                // 编辑模式下点击切换选中状态
                                if selectedSessionIds.contains(session.id) {
                                    selectedSessionIds.remove(session.id)
                                } else {
                                    selectedSessionIds.insert(session.id)
                                }
                            } else {
                                // 普通模式下点击选中会话
                                selectedSession = session
                                store.setCurrentViewingSession(session)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .confirmationDialog("确定要删除选中的 \(selectedSessionIds.count) 条录音吗？", isPresented: $showBatchDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                for sessionId in selectedSessionIds {
                    store.deleteSession(sessionId)
                }
                selectedSessionIds.removeAll()
                withAnimation {
                    isEditMode = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复")
        }
    }

    private var editModeToolbar: some View {
        HStack {
            Button("全选") {
                if selectedSessionIds.count == store.sessions.count {
                    selectedSessionIds.removeAll()
                } else {
                    selectedSessionIds = Set(store.sessions.map { $0.id })
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)

            Spacer()

            Text("已选 \(selectedSessionIds.count) 项")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Button("取消") {
                withAnimation {
                    isEditMode = false
                    selectedSessionIds.removeAll()
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)

            if !selectedSessionIds.isEmpty {
                Button(action: {
                    showBatchDeleteConfirmation = true
                }) {
                    Text("删除")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        ScrollView {
            VStack(spacing: 0) {
                if store.currentThoughtSegments.isEmpty {
                    emptyTimelineView
                } else {
                    // 使用 TimelineContainer 包装，绘制连续的中轴线
                    TimelineContainer {
                        ForEach(Array(store.currentThoughtSegments.enumerated()), id: \.element.id) { index, segment in
                            TimelineSegmentRow(
                                segment: segment,
                                isLeft: segment.isOnLeft,
                                isLast: index == store.currentThoughtSegments.count - 1,
                                // 优先使用选中的历史记录的开始时间，如果没有则使用当前录音会话的开始时间
                                sessionStartTime: selectedSession?.startTime ?? store.currentSession?.startTime
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyTimelineView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("暂无录音记录")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("点击左侧\"开始录音\"按钮开始")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: LongRecordingSession
    let isSelected: Bool
    let thoughtSegmentCount: Int
    var isEditMode: Bool = false
    var isChecked: Bool = false
    let onSelect: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var showRenameSheet = false
    @State private var newTitle = ""
    @State private var showCopySuccess = false

    var body: some View {
        HStack(spacing: 0) {
            // 编辑模式下显示选择框
            if isEditMode {
                Button(action: onSelect) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isChecked ? .accentColor : .secondary)
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
            }

            // 主要内容区域（可点击）
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // 收藏图标
                        if session.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                        }

                        Text(session.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(session.durationString)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("\(thoughtSegmentCount) 个思维段")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        if let preview = session.previewText {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(preview)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(isSelected && !isEditMode ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 操作按钮区域（非编辑模式）
            if !isEditMode {
                HStack(spacing: 4) {
                    // 收藏按钮
                    Button(action: {
                        LongRecordingStore.shared.toggleFavorite(session.id)
                    }) {
                        Image(systemName: session.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundColor(session.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(session.isFavorite ? "取消收藏" : "收藏")

                    // 删除按钮
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                }
                .padding(.trailing, 8)
                .opacity(isSelected ? 1 : 0.5)
            }
        }
        .contextMenu {
            // 右键菜单
            Button(action: {
                newTitle = session.title ?? ""
                showRenameSheet = true
            }) {
                Label("重命名", systemImage: "pencil")
            }

            Button(action: {
                copyAllText()
            }) {
                Label("复制全文", systemImage: "doc.on.doc")
            }

            Divider()

            Button(action: {
                LongRecordingStore.shared.toggleFavorite(session.id)
            }) {
                Label(
                    session.isFavorite ? "取消收藏" : "收藏",
                    systemImage: session.isFavorite ? "star.fill" : "star"
                )
            }

            Divider()

            Button(role: .destructive, action: {
                showDeleteConfirmation = true
            }) {
                Label("删除", systemImage: "trash")
            }
        }
        .confirmationDialog("确定要删除此录音吗？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                LongRecordingStore.shared.deleteSession(session.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复")
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(
                title: $newTitle,
                originalTitle: session.displayTitle,
                onConfirm: {
                    if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        LongRecordingStore.shared.renameSession(session.id, newTitle: newTitle.trimmingCharacters(in: .whitespaces))
                    }
                    showRenameSheet = false
                },
                onCancel: {
                    showRenameSheet = false
                }
            )
        }
        .overlay(
            Group {
                if showCopySuccess {
                    Text("已复制全文")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(6)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopySuccess = false
                                }
                            }
                        }
                }
            }
            , alignment: .center
        )
    }

    private func copyAllText() {
        let text = LongRecordingStore.shared.getAllThoughtSegmentsText(for: session.id)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            showCopySuccess = true
        }
    }
}

// MARK: - Rename Sheet

struct RenameSheet: View {
    @Binding var title: String
    let originalTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("重命名录音")
                .font(.headline)

            TextField("输入新名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .focused($isTextFieldFocused)
                .onSubmit {
                    onConfirm()
                }

            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("确定") {
                    onConfirm()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - Timeline Container（绘制连续中轴线）

struct TimelineContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 底层：连续的中轴线（贯穿整个列表）
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            // 上层：内容（用 VStack 确保垂直排列）
            VStack(alignment: .center, spacing: 0) {
                content
            }
        }
    }
}

// MARK: - Timeline Segment Row

struct TimelineSegmentRow: View {
    let segment: ThoughtSegment
    let isLeft: Bool
    let isLast: Bool
    var sessionStartTime: Date?
    @State private var showCopySuccess = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isLeft {
                // 左侧：对话框 → 间距 → 时间轴节点 → 空白
                segmentContent
                    .padding(.trailing, 12)  // 对话框与时间轴的间距

                // 时间轴节点（在中心线上）
                timelineNode

                Spacer()
                    .frame(minWidth: 50)  // 右侧最小空白
            } else {
                // 右侧：空白 → 时间轴节点 → 间距 → 对话框
                Spacer()
                    .frame(minWidth: 50)  // 左侧最小空白

                // 时间轴节点（在中心线上）
                timelineNode

                segmentContent
                    .padding(.leading, 12)  // 时间轴与对话框的间距
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, isLast ? 24 : 0)
        .overlay(
            // 复制成功提示
            Group {
                if showCopySuccess {
                    Text("已复制")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .cornerRadius(4)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation {
                                    showCopySuccess = false
                                }
                            }
                        }
                }
            }
            , alignment: .center
        )
    }

    /// 计算实际时间字符串（显示说话时的实际时间）
    private var actualTimeString: String {
        guard let startTime = sessionStartTime else {
            // 如果没有会话开始时间，回退到相对时间
            return segment.startTimeString
        }
        // 计算实际时间：会话开始时间 + 偏移量（毫秒转秒）
        let actualTime = startTime.addingTimeInterval(segment.startOffset / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: actualTime)
    }

    /// 复制文本到剪贴板
    private func copyText() {
        let text = segment.displayText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            showCopySuccess = true
        }
    }

    private var segmentContent: some View {
        VStack(alignment: isLeft ? .trailing : .leading, spacing: 4) {
            // 时间戳（放在靠近时间轴的位置）
            if isLeft {
                // 左侧：时间戳在右上方
                HStack(spacing: 4) {
                    Spacer()
                    if segment.isPolished {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    Text(actualTimeString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            } else {
                // 右侧：时间戳在左上方
                HStack(spacing: 4) {
                    Text(actualTimeString)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                    if segment.isPolished {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    Spacer()
                }
            }

            // 对话框卡片
            VStack(alignment: .leading, spacing: 6) {
                if !segment.displayText.isEmpty {
                    Text(segment.displayText)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("转写中...")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }

                // 底部操作栏
                HStack {
                    // 润色状态
                    if segment.isPolished {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                            Text("已润色")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.blue)
                    }

                    Spacer()

                    // 复制按钮
                    if !segment.displayText.isEmpty {
                        Button(action: copyText) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                Text("复制")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("复制文本")
                    }
                }
            }
            .padding(10)
            .frame(width: 220)  // 缩小约 20%（之前 280）
            .background(.regularMaterial)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
    }

    private var timelineNode: some View {
        VStack(spacing: 0) {
            // 节点圆点（在时间轴上）
            ZStack {
                Circle()
                    .fill(segment.isPolished ? Color.blue : Color.green)
                    .frame(width: 10, height: 10)

                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
            }

            if !isLast {
                Spacer().frame(minHeight: 20)
            }
        }
    }
}

// MARK: - Settings Sheet View (保留兼容性)

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsView()
            .frame(minWidth: 550, minHeight: 450)
    }
}

// MARK: - Settings Window Manager

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private var window: NSWindow?

    private init() {}

    /// Preload the settings window silently without showing it.
    /// This improves the first-time open speed by creating the window in advance.
    func preload() {
        guard window == nil else { return }
        createWindow()
    }

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        createWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Creates the settings window without showing it.
    private func createWindow() {
        guard window == nil else { return }

        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "设置"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.setFrameAutosaveName("SettingsWindow")
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
    }

    func close() {
        window?.close()
    }
}

// MARK: - Main Window Manager

@MainActor
final class MainWindowManager: NSObject {
    static let shared = MainWindowManager()
    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        // 检查窗口是否存在
        if let existingWindow = window {
            // 如果窗口最小化，先取消最小化
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            // 重新显示窗口（即使已关闭，因为 isReleasedWhenClosed = false）
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 窗口不存在，创建新窗口
        let mainWindow = MainWindowView()
        let hostingView = NSHostingView(rootView: mainWindow)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "VoxLink AI"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.setFrameAutosaveName("MainWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    func close() {
        window?.close()
    }
}

// MARK: - NSWindowDelegate

extension MainWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 窗口关闭时的处理（如果需要）
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 窗口成为主窗口时的处理（如果需要）
    }
}

// MARK: - Preview

#Preview("Main Window") {
    MainWindowView()
        .frame(width: 900, height: 600)
}

// MARK: - Quota Status Bar

struct QuotaStatusBar: View {
    let profile: UserProfile
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // 模式指示器行（所有用户显示）
            HStack {
                Image(systemName: modeIcon)
                    .font(.system(size: 10))
                    .foregroundColor(modeColor)
                Text(modeText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(modeColor)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 配额进度条（仅 Free 和 Pro 用户显示）
            if profile.userLevel != .basic {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 背景条
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))

                        // 使用量条
                        RoundedRectangle(cornerRadius: 2)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * CGFloat(profile.usagePercentage) / 100)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 12)
            }

            // 状态文字
            HStack {
                // 用户等级图标
                Image(systemName: levelIcon)
                    .font(.system(size: 10))
                    .foregroundColor(levelColor)

                Text(profile.userLevel.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // 剩余时长
                Text(quotaText)
                    .font(.system(size: 10))
                    .foregroundColor(quotaTextColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 未配置 Key 提示
            if !isBYOKConfigured {
                HStack(spacing: 4) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 9))
                    Text("请配置阿里云 API Key 以使用语音功能")
                        .font(.system(size: 9))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Helper Properties

    private var levelIcon: String {
        if let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty {
            return "key.fill"
        }
        return "person.fill"
    }

    private var levelColor: Color {
        if let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty {
            if SettingsStore.shared.isAliyunKeyValid {
                return .green
            }
            return .orange
        }
        return .secondary
    }

    // MARK: - Mode Properties

    private var isBYOKConfigured: Bool {
        if let key = APIKeyStore.shared.aliyunASRAPIKey, !key.isEmpty {
            return true
        }
        return false
    }

    private var modeIcon: String {
        if isBYOKConfigured {
            if SettingsStore.shared.isAliyunKeyValid {
                return "bolt.fill"
            }
            return "exclamationmark.triangle"
        }
        return "key"
    }

    private var modeText: String {
        if isBYOKConfigured {
            if SettingsStore.shared.isAliyunKeyValid {
                return "BYOK 模式"
            }
            return "Key 待验证"
        }
        return "未配置 Key"
    }

    private var modeColor: Color {
        if isBYOKConfigured {
            if SettingsStore.shared.isAliyunKeyValid {
                return .green
            }
            return .orange
        }
        return .orange
    }

    private var progressColor: Color {
        return .accentColor
    }

    private var quotaText: String {
        if isBYOKConfigured {
            return "使用您自己的配额"
        }
        return "未配置 Key"
    }

    private var quotaTextColor: Color {
        if isBYOKConfigured {
            return .secondary
        }
        return .orange
    }

    private var warningColor: Color {
        return .orange
    }
}
