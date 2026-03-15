//
//  LocalizationService.swift
//  VoxLink
//
//  本地化服务 - 管理应用语言设置和字符串本地化
//

import Foundation
import Combine

/// 支持的语言
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        }
    }
}

/// 本地化服务
class LocalizationService: ObservableObject {
    static let shared = LocalizationService()

    /// 当前语言
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Keys.language)
        }
    }

    private init() {
        // 从 UserDefaults 读取保存的语言，默认英文
        if let savedLang = UserDefaults.standard.string(forKey: Keys.language),
           let lang = AppLanguage(rawValue: savedLang) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .english
        }
    }

    // MARK: - String Keys

    struct Keys {
        static let language = "app_language"
    }

    // MARK: - Localized Strings

    /// 获取本地化字符串
    func localized(_ key: String) -> String {
        return strings[key]?[currentLanguage] ?? key
    }

    /// 所有本地化字符串
    private let strings: [String: [AppLanguage: String]] = [
        // MARK: - App
        "app.name": [
            .english: "VoxLink AI",
            .chinese: "VoxLink AI"
        ],
        "app.subtitle": [
            .english: "Speak the trade",
            .chinese: "开口复盘"
        ],

        // MARK: - Login
        "login.title": [
            .english: "Login",
            .chinese: "登录"
        ],
        "login.email": [
            .english: "Email Address",
            .chinese: "邮箱地址"
        ],
        "login.email_placeholder": [
            .english: "name@example.com",
            .chinese: "name@example.com"
        ],
        "login.send_code": [
            .english: "Send Code",
            .chinese: "发送验证码"
        ],
        "login.verification_code": [
            .english: "Verification Code",
            .chinese: "验证码"
        ],
        "login.code_placeholder": [
            .english: "Enter 6-digit code",
            .chinese: "请输入 6 位验证码"
        ],
        "login.login": [
            .english: "Login",
            .chinese: "登录"
        ],
        "login.code_sent_to": [
            .english: "Code sent to",
            .chinese: "验证码已发送至"
        ],
        "login.resend": [
            .english: "Resend",
            .chinese: "重新发送"
        ],
        "login.change_email": [
            .english: "Change Email",
            .chinese: "更换邮箱"
        ],
        "login.first_time_hint": [
            .english: "First time? Account will be created automatically",
            .chinese: "首次登录将自动创建账号"
        ],
        "login.step_email": [
            .english: "Email",
            .chinese: "邮箱"
        ],
        "login.step_verify": [
            .english: "Verify",
            .chinese: "验证"
        ],
        "login.terms_hint": [
            .english: "By logging in, you agree to our Terms of Service and Privacy Policy",
            .chinese: "登录即表示您同意我们的服务条款和隐私政策"
        ],
        "login.seconds": [
            .english: "s",
            .chinese: "秒后可重新发送"
        ],

        // MARK: - Settings
        "settings.title": [
            .english: "Settings",
            .chinese: "设置"
        ],
        "settings.general": [
            .english: "General",
            .chinese: "通用"
        ],
        "settings.language": [
            .english: "Language",
            .chinese: "语言"
        ],
        "settings.language_note": [
            .english: "Restart app for full effect",
            .chinese: "重启应用以完全生效"
        ],
        "settings.theme": [
            .english: "Theme",
            .chinese: "主题"
        ],
        "settings.theme_system": [
            .english: "System",
            .chinese: "跟随系统"
        ],
        "settings.theme_light": [
            .english: "Light",
            .chinese: "浅色模式"
        ],
        "settings.theme_dark": [
            .english: "Dark",
            .chinese: "深色模式"
        ],
        "settings.recording": [
            .english: "Recording",
            .chinese: "录音"
        ],
        "settings.hotkey": [
            .english: "Hotkey",
            .chinese: "快捷键"
        ],
        "settings.press_hold": [
            .english: "Press and Hold",
            .chinese: "按住说话"
        ],
        "settings.press_hold_desc": [
            .english: "Hold to record, release to stop",
            .chinese: "按住录音，松开停止"
        ],
        "settings.ai_enhancement": [
            .english: "AI Enhancement",
            .chinese: "AI 润色"
        ],
        "settings.ai_enhancement_desc": [
            .english: "Polish transcripts with AI",
            .chinese: "使用 AI 优化转录文本"
        ],
        "settings.account": [
            .english: "Account",
            .chinese: "账户"
        ],
        "settings.account_info": [
            .english: "Account Info",
            .chinese: "账户信息"
        ],
        "settings.quota": [
            .english: "Quota",
            .chinese: "配额"
        ],
        "settings.quota_remaining": [
            .english: "Remaining",
            .chinese: "剩余"
        ],
        "settings.unlimited": [
            .english: "Unlimited",
            .chinese: "无限制"
        ],
        "settings.logout": [
            .english: "Log Out",
            .chinese: "退出登录"
        ],
        "settings.about": [
            .english: "About",
            .chinese: "关于"
        ],
        "settings.dock_icon": [
            .english: "Show in Dock",
            .chinese: "在 Dock 中显示"
        ],
        "settings.launch_at_login": [
            .english: "Launch at Login",
            .chinese: "登录时启动"
        ],
        "settings.api_settings": [
            .english: "API Settings",
            .chinese: "API 设置"
        ],
        "settings.server_url": [
            .english: "Server URL",
            .chinese: "服务器地址"
        ],
        "settings.api_key": [
            .english: "API Key",
            .chinese: "API 密钥"
        ],
        "settings.api_key_hint": [
            .english: "Optional: Use your own Aliyun API key",
            .chinese: "可选：使用您自己的阿里云 API 密钥"
        ],

        // MARK: - Recording
        "recording.listening": [
            .english: "Listening...",
            .chinese: "正在听写..."
        ],
        "recording.processing": [
            .english: "Processing...",
            .chinese: "处理中..."
        ],
        "recording.click_to_start": [
            .english: "Click to start recording",
            .chinese: "点击开始录音"
        ],
        "recording.no_speech": [
            .english: "No speech detected",
            .chinese: "未检测到语音"
        ],

        // MARK: - Errors
        "error.login_failed": [
            .english: "Login failed",
            .chinese: "登录失败"
        ],
        "error.network": [
            .english: "Network error",
            .chinese: "网络错误"
        ],
        "error.quota_exceeded": [
            .english: "Daily quota exceeded",
            .chinese: "今日配额已用完"
        ],
        "error.api_key_required": [
            .english: "Please configure API key",
            .chinese: "请先配置 API 密钥"
        ],

        // MARK: - History
        "history.title": [
            .english: "History",
            .chinese: "历史记录"
        ],
        "history.empty": [
            .english: "No history yet",
            .chinese: "暂无历史记录"
        ],
        "history.clear": [
            .english: "Clear History",
            .chinese: "清除历史"
        ],
        "history.copy": [
            .english: "Copy",
            .chinese: "复制"
        ],
        "history.delete": [
            .english: "Delete",
            .chinese: "删除"
        ],
        "history.copied": [
            .english: "Copied",
            .chinese: "已复制"
        ],

        // MARK: - Time Anchor
        "anchor.title": [
            .english: "Time Anchor",
            .chinese: "时光锚点"
        ],
        "anchor.chart": [
            .english: "Chart",
            .chinese: "图表"
        ],
        "anchor.replay": [
            .english: "Replay",
            .chinese: "回放"
        ],

        // MARK: - About
        "about.version": [
            .english: "Version",
            .chinese: "版本"
        ],
        "about.developer": [
            .english: "Developer",
            .chinese: "开发者"
        ],
        "about.website": [
            .english: "Website",
            .chinese: "网站"
        ],

        // MARK: - Common
        "common.ok": [
            .english: "OK",
            .chinese: "确定"
        ],
        "common.cancel": [
            .english: "Cancel",
            .chinese: "取消"
        ],
        "common.save": [
            .english: "Save",
            .chinese: "保存"
        ],
        "common.close": [
            .english: "Close",
            .chinese: "关闭"
        ],
        "common.yes": [
            .english: "Yes",
            .chinese: "是"
        ],
        "common.no": [
            .english: "No",
            .chinese: "否"
        ],
        "common.minutes": [
            .english: "min",
            .chinese: "分钟"
        ],
        "common.seconds": [
            .english: "sec",
            .chinese: "秒"
        ]
    ]
}

// MARK: - Convenience Function

/// 获取本地化字符串的快捷方法
func L(_ key: String) -> String {
    return LocalizationService.shared.localized(key)
}
