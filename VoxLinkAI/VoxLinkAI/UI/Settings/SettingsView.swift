//
//  SettingsView.swift
//  VoxLink
//
//  偏好设置视图
//

import SwiftUI

/// 偏好设置视图
struct SettingsView: View {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var appServices = AppServices.shared
    @StateObject private var localization = LocalizationService.shared

    @State private var selectedTab = 0
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown

    enum ConnectionStatus {
        case unknown
        case success
        case failed
        case testing
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(
                settings: settings,
                isTestingConnection: $isTestingConnection,
                connectionStatus: $connectionStatus
            )
            .tabItem {
                Label(L("settings.general"), systemImage: "gearshape")
            }
            .tag(0)

            HotkeySettingsView(settings: settings)
                .tabItem {
                    Label(L("settings.hotkey"), systemImage: "keyboard")
                }
                .tag(1)

            AccountSettingsView()
                .tabItem {
                    Label(L("settings.account"), systemImage: "person.circle")
                }
                .tag(2)

            AboutSettingsView()
                .tabItem {
                    Label(L("settings.about"), systemImage: "info.circle")
                }
                .tag(3)
        }
        .frame(minWidth: 550, minHeight: 450)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Binding var isTestingConnection: Bool
    @Binding var connectionStatus: SettingsView.ConnectionStatus
    @StateObject private var localization = LocalizationService.shared

    @State private var showAPIKey: Bool = false
    // 初始化 lastValidatedKey：如果之前已验证过，使用当前 key
    @State private var lastValidatedKey: String = {
        let settings = SettingsStore.shared
        if settings.isAliyunKeyValid && !settings.aliyunAPIKey.isEmpty {
            return settings.aliyunAPIKey
        }
        return ""
    }()

    var body: some View {
        Form {
            // MARK: - 阿里云 API Key (BYOK)
            Section(header: Text("阿里云 API Key (可选)")) {
                // API Key 输入
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: $settings.aliyunAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.aliyunAPIKey) { newValue in
                                handleAPIKeyChange(newValue)
                            }
                    } else {
                        SecureField("API Key", text: $settings.aliyunAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.aliyunAPIKey) { newValue in
                                handleAPIKeyChange(newValue)
                            }
                    }

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(showAPIKey ? "隐藏" : "显示")
                }

                // 区域选择
                Picker("区域", selection: $settings.aliyunRegion) {
                    Text("北京（中国内地）").tag("server")
                    Text("新加坡（国际）").tag("singapore")
                }
                .pickerStyle(.menu)
                .frame(width: 200)

                // 测试连接按钮
                HStack {
                    Button(action: testDirectConnection) {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 20, height: 20)
                        } else {
                            Text("测试连接")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingConnection || settings.aliyunAPIKey.isEmpty)

                    connectionStatusIcon
                }

                // 帮助提示
                VStack(alignment: .leading, spacing: 4) {
                    Text("填入您自己的阿里云 API Key，可以不消耗我们的配额")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("获取 API Key:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link("https://dashscope.console.aliyun.com/",
                         destination: URL(string: "https://dashscope.console.aliyun.com/")!)
                        .font(.caption)
                }
            }

            // MARK: - 应用设置
            Section(header: Text(L("settings.general"))) {
                // 语言选择
                Picker(selection: $localization.currentLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        HStack(spacing: 8) {
                            Text(lang.flag)
                            Text(lang.displayName)
                        }
                        .tag(lang)
                    }
                } label: {
                    Text(L("settings.language"))
                }
                .frame(width: 200)

                Text(L("settings.language_note"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                // 主题选择
                Picker(selection: $settings.appTheme) {
                    ForEach(VoxLinkTheme.allCases, id: \.self) { theme in
                        HStack(spacing: 8) {
                            Image(systemName: theme.icon)
                            Text(theme.displayName)
                        }
                        .tag(theme)
                    }
                } label: {
                    Text(L("settings.theme"))
                }

                Toggle(L("settings.dock_icon"), isOn: $settings.showInDock)
                Toggle(L("settings.launch_at_login"), isOn: $settings.launchAtLogin)
                Toggle("结果窗口自动关闭", isOn: $settings.autoCloseResultWindow)

                if settings.autoCloseResultWindow {
                    Text("复制完成后自动关闭结果窗口")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("结果窗口需手动关闭")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            // 如果之前已验证过，初始化 lastValidatedKey
            if settings.isAliyunKeyValid && !settings.aliyunAPIKey.isEmpty {
                lastValidatedKey = settings.aliyunAPIKey
            }
        }
    }

    // MARK: - Connection Status Icon

    @ViewBuilder
    private var connectionStatusIcon: some View {
        switch connectionStatus {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .testing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 20, height: 20)
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Connection Test Methods
    private func testDirectConnection() {
        isTestingConnection = true
        connectionStatus = .testing

        Task {
            // 使用阿里云客户端测试连接
            let mode: AliyunASRMode = settings.aliyunRegion == "singapore" ? .singapore : .server
            let client = AliyunASRClient(apiKey: settings.aliyunAPIKey, mode: mode)

            // 创建 0.5 秒的静音 PCM 数据进行测试
            let silentPCM = Data(repeating: 0, count: 16000)

            do {
                let result = try await client.transcribe(pcmData: silentPCM)
                // 静音数据可能返回成功但没有文本，或返回"未检测到语音"
                let success = result.success || result.error == "未检测到语音"

                await MainActor.run {
                    connectionStatus = success ? .success : .failed
                    isTestingConnection = false

                    // 测试成功后标记 Key 为有效
                    if success {
                        settings.isAliyunKeyValid = true
                        lastValidatedKey = settings.aliyunAPIKey
                        print("[SettingsView] API Key validated successfully")
                    }
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed
                    isTestingConnection = false
                }
            }
        }
    }

    /// 处理 API Key 输入变化（防呆逻辑）
    private func handleAPIKeyChange(_ newValue: String) {
        // 1. 自动净化：去除首尾空格和换行符
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果值需要修正，更新它
        if trimmed != newValue {
            DispatchQueue.main.async {
                settings.aliyunAPIKey = trimmed
            }
            return // onChange 会再次触发，使用修正后的值
        }

        // 2. 清空即回退：如果净化后为空，删除 Key 并标记无效
        if trimmed.isEmpty {
            APIKeyStore.shared.aliyunASRAPIKey = nil
            settings.isAliyunKeyValid = false
            lastValidatedKey = ""
            print("[SettingsView] API Key cleared")
            return
        }

        // 3. 编辑即失效：如果与上次验证成功的 Key 不同，标记为无效
        if trimmed != lastValidatedKey && settings.isAliyunKeyValid {
            settings.isAliyunKeyValid = false
            print("[SettingsView] API Key modified, marked as unvalidated")
        }
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @ObservedObject var settings: SettingsStore

    /// 当前快捷键的显示名称
    private var currentHotkeyName: String {
        HotkeyDefinition.displayName(for: settings.hotkeyKeyCode)
    }

    /// 当前快捷键的符号
    private var currentHotkeySymbol: String {
        HotkeyDefinition.symbol(for: settings.hotkeyKeyCode)
    }

    var body: some View {
        Form {
            // MARK: - 快捷键汇总
            Section(header: Text("快捷键汇总")) {
                VStack(alignment: .leading, spacing: 0) {
                    // 全局快捷键
                    Text("全局快捷键")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    HotkeyRow(key: currentHotkeySymbol, description: "开始/停止录音", isGlobal: true)

                    Divider()
                        .padding(.vertical, 8)

                    // 应用内快捷键
                    Text("应用内快捷键")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)

                    HotkeyRow(key: "⌘R", description: "开始录音")
                    HotkeyRow(key: "⌘1", description: "显示主窗口")
                    HotkeyRow(key: "⌘2", description: "历史记录")
                    HotkeyRow(key: "⌘,", description: "偏好设置")
                }
            }

            // MARK: - 录音快捷键设置
            Section(header: Text("录音快捷键设置")) {
                VStack(alignment: .leading, spacing: 12) {
                    // 快捷键选择器
                    HStack {
                        Text("录音快捷键:")
                            .frame(width: 100, alignment: .leading)

                        Picker("", selection: $settings.hotkeyKeyCode) {
                            Text("⌥ Option").tag(UInt16(58))
                            Text("⌃ Control").tag(UInt16(59))
                            Text("⌘ Command").tag(UInt16(55))
                            Text("⇧ Shift").tag(UInt16(56))
                            Text("fn Fn").tag(UInt16(63))
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }

                    Picker("触发模式", selection: $settings.pressAndHoldMode) {
                        Text("按住说话").tag(true)
                        Text("点击切换").tag(false)
                    }
                    .pickerStyle(.radioGroup)

                    if settings.pressAndHoldMode {
                        VStack(alignment: .leading) {
                            Text("长按取消阈值: \(settings.longPressCancelMs) ms")
                            Slider(value: Binding(
                                get: { Double(settings.longPressCancelMs) },
                                set: { settings.longPressCancelMs = Int($0) }
                            ), in: 100...1000, step: 50)
                            Text("按住超过此时间后自动取消录音")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // MARK: - 使用说明
            Section(header: Text("使用说明")) {
                VStack(alignment: .leading, spacing: 8) {
                    if settings.pressAndHoldMode {
                        Text("• 按住 \(currentHotkeyName) 开始录音")
                        Text("• 松开 \(currentHotkeyName) 结束录音并发送")
                        Text("• 如果按住时间超过阈值，录音将被取消")
                    } else {
                        Text("• 按 \(currentHotkeyName) 开始录音")
                        Text("• 再按 \(currentHotkeyName) 结束录音并发送")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Hotkey Row

struct HotkeyRow: View {
    let key: String
    let description: String
    var isGlobal: Bool = false

    var body: some View {
        HStack {
            Text(description)
                .frame(width: 120, alignment: .leading)

            Spacer()

            HStack(spacing: 4) {
                if isGlobal {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    /// 从 Info.plist 读取版本号
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }

    // 网站基础 URL（从配置读取）
    private var websiteBaseURL: String { SupabaseConfig.websiteBaseURL }

    var body: some View {
        Form {
            // MARK: - 应用信息
            Section {
                VStack(spacing: 16) {
                    // App 图标
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    } else {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.voxlinkAccent)
                    }

                    Text("VoxLink AI")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(appVersion)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Copyright © 2026 VoxLink AI. All rights reserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // MARK: - 法律文档（浏览器链接）— 仅在配置了网站 URL 时显示
            if !websiteBaseURL.isEmpty {
                Section(header: Text("法律文档")) {
                    if let privacyURL = URL(string: "\(websiteBaseURL)/privacy") {
                        Link(destination: privacyURL) {
                            HStack {
                                Label("隐私政策", systemImage: "hand.raised.fill")
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let termsURL = URL(string: "\(websiteBaseURL)/terms") {
                        Link(destination: termsURL) {
                            HStack {
                                Label("用户协议", systemImage: "doc.text.fill")
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: - 开源许可证
            Section(header: Text("开源许可证")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本软件使用以下开源库：")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Link("Supabase Swift - MIT License",
                         destination: URL(string: "https://github.com/supabase/supabase-swift")!)
                        .font(.subheadline)

                    Link("ONNX Runtime - MIT License",
                         destination: URL(string: "https://github.com/microsoft/onnxruntime")!)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Account Settings

struct AccountSettingsView: View {
    @StateObject private var auth = SupabaseService.shared

    var body: some View {
        Form {
            if auth.isAuthenticated {
                Section(header: Text("个人信息")) {
                    HStack {
                        Text("邮箱")
                        Spacer()
                        Text(auth.userEmail ?? "未知")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive, action: {
                        Task {
                            try? await auth.signOut()
                        }
                    }) {
                        Text("退出登录")
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("尚未登录")
                        .font(.headline)
                    Button("立即登录") {
                        // 逻辑：显示登录窗口
                        LoginWindowManager.shared.show()
                        SettingsWindowManager.shared.close()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .frame(width: 600, height: 500)
}
