//
//  SettingsStore.swift
//  VoxLink
//
//  用户设置存储
//

import AppKit
import Combine
import Foundation

/// 应用主题模式
enum VoxLinkTheme: String, CaseIterable {
    case system = "system"   // 跟随系统
    case light = "light"     // 浅色模式
    case dark = "dark"       // 深色模式

    var displayName: String {
        switch self {
        case .system: return L("settings.theme_system")
        case .light: return L("settings.theme_light")
        case .dark: return L("settings.theme_dark")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// 用户设置存储
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // MARK: - Published Settings

    /// API 基础 URL（从 Secrets.plist 配置读取）
    /// DEBUG 模式下可切换为本地服务器
    #if DEBUG
    @Published var apiBaseURL: String {
        didSet { UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL) }
    }
    #else
    var apiBaseURL: String {
        return SupabaseConfig.apiBaseURL
    }
    #endif

    /// 阿里云 API Key（直连模式）
    @Published var aliyunAPIKey: String {
        didSet { APIKeyStore.shared.aliyunASRAPIKey = aliyunAPIKey.isEmpty ? nil : aliyunAPIKey }
    }

    /// 阿里云区域（直连模式）
    @Published var aliyunRegion: String {
        didSet { UserDefaults.standard.set(aliyunRegion, forKey: Keys.aliyunRegion) }
    }

    /// 阿里云 API Key 是否已验证
    /// 用户编辑后需重新点击"测试连接"按钮验证
    @Published var isAliyunKeyValid: Bool {
        didSet { UserDefaults.standard.set(isAliyunKeyValid, forKey: Keys.isAliyunKeyValid) }
    }

    /// 是否在 Dock 中显示
    @Published var showInDock: Bool {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: Keys.showInDock)
            updateDockIcon()
        }
    }

    /// 登录时启动
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// 快捷键键码 (默认 Option 键 = 58)
    @Published var hotkeyKeyCode: UInt16 {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    /// 按住模式 (true = 按住说话，松开停止; false = 点击开始/停止)
    @Published var pressAndHoldMode: Bool {
        didSet { UserDefaults.standard.set(pressAndHoldMode, forKey: Keys.pressAndHoldMode) }
    }

    /// 长按取消阈值 (毫秒)
    @Published var longPressCancelMs: Int {
        didSet { UserDefaults.standard.set(longPressCancelMs, forKey: Keys.longPressCancelMs) }
    }

    /// 结果窗口自动关闭
    @Published var autoCloseResultWindow: Bool {
        didSet { UserDefaults.standard.set(autoCloseResultWindow, forKey: Keys.autoCloseResultWindow) }
    }

    /// 应用主题
    @Published var appTheme: VoxLinkTheme {
        didSet {
            UserDefaults.standard.set(appTheme.rawValue, forKey: Keys.appTheme)
            applyTheme()
        }
    }

    /// 思维段静音触发时长（秒）- 静音超过此时长后触发 AI 润色
    /// 默认 30 秒，可调整为 10-120 秒
    @Published var thoughtSegmentSilenceSeconds: Int {
        didSet { UserDefaults.standard.set(thoughtSegmentSilenceSeconds, forKey: Keys.thoughtSegmentSilenceSeconds) }
    }

    /// 本地头像路径
    @Published var localAvatarPath: String? {
        didSet { UserDefaults.standard.set(localAvatarPath, forKey: Keys.localAvatarPath) }
    }

    // MARK: - Keys

    private enum Keys {
        static let apiBaseURL = "apiBaseURL"
        static let aliyunRegion = "aliyunRegion"
        static let isAliyunKeyValid = "isAliyunKeyValid"
        static let showInDock = "showInDock"
        static let launchAtLogin = "launchAtLogin"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let pressAndHoldMode = "pressAndHoldMode"
        static let longPressCancelMs = "longPressCancelMs"
        static let autoCloseResultWindow = "autoCloseResultWindow"
        static let appTheme = "appTheme"
        static let thoughtSegmentSilenceSeconds = "thoughtSegmentSilenceSeconds"
        static let localAvatarPath = "localAvatarPath"
    }

    // MARK: - Initialization

    private init() {
        #if DEBUG
        // DEBUG 模式：允许切换服务器地址
        // 迁移：将旧的 localhost 地址更新为配置地址
        let savedURL = UserDefaults.standard.string(forKey: Keys.apiBaseURL)
        let configuredURL = SupabaseConfig.apiBaseURL
        if let url = savedURL, url.contains("localhost") || url.contains("127.0.0.1") {
            // 旧的开发地址，更新为配置地址
            self.apiBaseURL = configuredURL
            print("[SettingsStore] Migrated localhost URL to configured URL")
        } else {
            self.apiBaseURL = savedURL ?? configuredURL
        }
        #endif

        // 加载 API Key（优先从 Keychain，DEBUG 模式下可从环境变量加载默认值）
        var savedAPIKey = APIKeyStore.shared.aliyunASRAPIKey ?? ""

        #if DEBUG
        // DEBUG 模式：如果用户没有配置 API Key，尝试从环境变量或 .env 文件读取
        if savedAPIKey.isEmpty {
            savedAPIKey = Self.loadDebugAPIKey()
            if !savedAPIKey.isEmpty {
                print("[SettingsStore] DEBUG: Loaded API key from environment")
                // 保存到 Keychain，这样下次启动就不需要再读取了
                APIKeyStore.shared.aliyunASRAPIKey = savedAPIKey
            }
        }
        #endif

        self.aliyunAPIKey = savedAPIKey
        self.aliyunRegion = UserDefaults.standard.string(forKey: Keys.aliyunRegion) ?? "server" // server = 北京, singapore = 新加坡
        self.isAliyunKeyValid = UserDefaults.standard.object(forKey: Keys.isAliyunKeyValid) as? Bool ?? false
        self.showInDock = UserDefaults.standard.object(forKey: Keys.showInDock) as? Bool ?? true
        self.launchAtLogin = UserDefaults.standard.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.hotkeyKeyCode = UserDefaults.standard.object(forKey: Keys.hotkeyKeyCode) as? UInt16 ?? 58 // Option 键
        self.pressAndHoldMode = UserDefaults.standard.object(forKey: Keys.pressAndHoldMode) as? Bool ?? false  // 默认使用点击模式（与 Python 版本一致）
        self.longPressCancelMs = UserDefaults.standard.object(forKey: Keys.longPressCancelMs) as? Int ?? 300
        self.autoCloseResultWindow = UserDefaults.standard.object(forKey: Keys.autoCloseResultWindow) as? Bool ?? false  // 默认不自动关闭

        // 加载主题设置
        let savedTheme = UserDefaults.standard.string(forKey: Keys.appTheme) ?? "system"
        self.appTheme = VoxLinkTheme(rawValue: savedTheme) ?? .system

        // 加载思维段静音触发时长
        self.thoughtSegmentSilenceSeconds = UserDefaults.standard.object(forKey: Keys.thoughtSegmentSilenceSeconds) as? Int ?? 20

        // 加载本地头像路径
        self.localAvatarPath = UserDefaults.standard.string(forKey: Keys.localAvatarPath)
    }

    // MARK: - Theme

    /// 应用主题
    func applyTheme() {
        DispatchQueue.main.async {
            switch self.appTheme {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    // MARK: - DEBUG Helpers

    #if DEBUG
    /// 从环境变量或 .env 文件加载 API Key（仅 DEBUG 模式）
    /// 设为 internal 以便 SettingsView 可以调用
    static func loadDebugAPIKey() -> String {
        // 1. 首先尝试从系统环境变量读取
        if let envKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"], !envKey.isEmpty {
            print("[SettingsStore] Found DASHSCOPE_API_KEY in environment")
            return envKey
        }

        // 2. 尝试从多个可能的 .env 文件路径读取
        let currentDir = FileManager.default.currentDirectoryPath
        let envPaths = [
            // 当前目录
            currentDir + "/.env",
            // 向上逐级查找（Xcode 项目目录层级较深）
            URL(fileURLWithPath: currentDir).deletingLastPathComponent().path + "/.env",
            URL(fileURLWithPath: currentDir).deletingLastPathComponent().deletingLastPathComponent().path + "/.env",
            URL(fileURLWithPath: currentDir).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path + "/.env",
            URL(fileURLWithPath: currentDir).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path + "/.env",
            // 用户主目录的 .voxlinkai/.env
            NSHomeDirectory() + "/.voxlinkai/.env"
        ]

        for path in envPaths {
            print("[SettingsStore] Checking: \(path)")
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("DASHSCOPE_API_KEY=") {
                        let value = trimmed
                            .replacingOccurrences(of: "DASHSCOPE_API_KEY=", with: "")
                            .replacingOccurrences(of: "\"", with: "")
                            .replacingOccurrences(of: "'", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty {
                            print("[SettingsStore] Found DASHSCOPE_API_KEY in \(path)")
                            return value
                        }
                    }
                }
            }
        }

        print("[SettingsStore] No DASHSCOPE_API_KEY found in any .env file")
        return ""
    }
    #endif

    // MARK: - Methods

    /// 初始化默认值
    func initializeDefaults() {
        // 确保所有默认值都已设置
        if UserDefaults.standard.string(forKey: Keys.apiBaseURL) == nil {
            UserDefaults.standard.set(apiBaseURL, forKey: Keys.apiBaseURL)
        }
    }

    /// 更新 Dock 图标显示
    private func updateDockIcon() {
        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// 重置为默认设置
    func resetToDefaults() {
        // apiBaseURL 是常量，不需要重置
        aliyunAPIKey = ""
        aliyunRegion = "server"
        showInDock = true
        launchAtLogin = false
        hotkeyKeyCode = 58
        pressAndHoldMode = true
        longPressCancelMs = 300
        autoCloseResultWindow = false
        thoughtSegmentSilenceSeconds = 20
    }

    /// 检查是否已配置（始终返回 true，因为现在统一使用直连模式）
    var isConfigured: Bool {
        return true
    }

    /// 获取当前模式的描述
    var currentModeDescription: String {
        let region = aliyunRegion == "singapore" ? "新加坡" : "北京"
        if !aliyunAPIKey.isEmpty {
            return "直连阿里云 (\(region)) - 自备 Key"
        } else {
            return "直连阿里云 (\(region)) - 服务器授权"
        }
    }
}
