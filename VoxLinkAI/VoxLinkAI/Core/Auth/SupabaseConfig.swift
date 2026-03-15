//
//  SupabaseConfig.swift
//  VoxLink
//
//  Supabase 配置读取
//  开源版本：用户需要自行配置 SUPABASE_URL 和 SUPABASE_ANON_KEY
//  1. 复制 Secrets.example.plist 并重命名为 Secrets.plist
//  2. 填入您自己的 Supabase 项目凭证
//  或者在 Info.plist 中配置相应的键值
//

import Foundation

/// Supabase 配置
enum SupabaseConfig {

    // MARK: - Private

    /// 从 Secrets.plist 加载配置字典
    private static var secretsDict: [String: Any]? {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist") else {
            #if DEBUG
            print("[SupabaseConfig] Secrets.plist not found in bundle")
            #endif
            return nil
        }
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            #if DEBUG
            print("[SupabaseConfig] Failed to parse Secrets.plist")
            #endif
            return nil
        }
        return dict
    }

    /// 从 Info.plist 或 Secrets.plist 读取字符串配置
    private static func getString(_ key: String) -> String? {
        // 优先从 Secrets.plist 读取
        if let secrets = secretsDict,
           let value = secrets[key] as? String,
           !value.isEmpty,
           !value.contains("your-") {
            return value
        }
        // 回退到 Info.plist
        if let value = Bundle.main.infoDictionary?[key] as? String,
           !value.isEmpty,
           !value.contains("your-") {
            return value
        }
        return nil
    }

    // MARK: - Public

    /// Supabase 项目 URL
    /// 如果未配置且 USE_MOCK_AUTH=true，返回空 URL（不会被使用）
    static var supabaseURL: URL {
        guard let urlString = getString("SUPABASE_URL"),
              let url = URL(string: urlString) else {
            // 未配置时返回空 URL，配合 USE_MOCK_AUTH=true 使用
            return URL(string: "about:blank")!
        }
        return url
    }

    /// Supabase Anon Key（公开密钥，可以暴露在客户端）
    /// 如果未配置且 USE_MOCK_AUTH=true，返回空字符串（不会被使用）
    static var supabaseAnonKey: String {
        guard let key = getString("SUPABASE_ANON_KEY") else {
            // 未配置时返回空字符串，配合 USE_MOCK_AUTH=true 使用
            return ""
        }
        return key
    }

    /// 是否跳过 Supabase 登录（BYOK 模式）
    /// 设置为 true 时直接进入应用，无需配置 Supabase
    static var useMockData: Bool {
        // 优先从 Secrets.plist 读取
        if let secrets = secretsDict,
           let value = secrets["USE_MOCK_AUTH"] as? Bool {
            return value
        }
        // 回退到 Info.plist
        return Bundle.main.infoDictionary?["USE_MOCK_AUTH"] as? Bool ?? false
    }

    /// Dodo Payments Basic 计划支付链接
    static var dodoBasicUrl: String {
        getString("DODO_BASIC_URL") ?? ""
    }

    /// Dodo Payments Pro 计划支付链接
    static var dodoProUrl: String {
        getString("DODO_PRO_URL") ?? ""
    }

    /// 后端 API 基础 URL（可选，开源用户可不配置）
    /// 从 Secrets.plist 的 API_BASE_URL 读取，默认为空字符串（表示未配置）
    static var apiBaseURL: String {
        if let secrets = secretsDict,
           let value = secrets["API_BASE_URL"] as? String,
           !value.isEmpty {
            return value
        }
        if let value = Bundle.main.infoDictionary?["API_BASE_URL"] as? String,
           !value.isEmpty {
            return value
        }
        return ""
    }

    /// 网站基础 URL（用于隐私政策、下载页面等链接）
    /// 从 Secrets.plist 的 WEBSITE_BASE_URL 读取，默认保留上游项目链接
    static var websiteBaseURL: String {
        if let secrets = secretsDict,
           let value = secrets["WEBSITE_BASE_URL"] as? String,
           !value.isEmpty {
            return value
        }
        if let value = Bundle.main.infoDictionary?["WEBSITE_BASE_URL"] as? String,
           !value.isEmpty {
            return value
        }
        return "https://voxlinkai.com"
    }

    /// 检查配置是否有效
    static var isConfigured: Bool {
        guard let url = getString("SUPABASE_URL"),
              let key = getString("SUPABASE_ANON_KEY"),
              !url.isEmpty, !key.isEmpty else {
            return false
        }
        return true
    }
}
