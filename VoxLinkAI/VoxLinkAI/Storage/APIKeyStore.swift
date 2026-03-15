//
//  APIKeyStore.swift
//  VoxLink
//
//  API Key 安全存储 - 使用 Keychain 存储敏感信息
//

import Foundation
import Security

/// API Key 安全存储
///
/// 使用 macOS 标准 Keychain 存储 API Key。
/// 注意：开发者反复编译时可能触发 Keychain 密码弹窗（因为签名变化），
/// 这是 macOS 的正常安全行为。DMG 分发的用户不会遇到此问题。
final class APIKeyStore {
    static let shared = APIKeyStore()

    // MARK: - Keychain Keys

    private enum KeychainKey {
        static let aliyunASR = "com.voxlinkai.aliyun.asr.apikey"
        static let aliyunAI = "com.voxlinkai.aliyun.ai.apikey"
        static let authToken = "com.voxlinkai.auth.token"
    }

    /// 固定的 service name，避免 bundleIdentifier 变化导致 Keychain 条目丢失
    private static let serviceName = "com.voxlinkai.VoxLinkAI"

    // MARK: - Properties

    /// 阿里云 ASR API Key（DashScope）
    var aliyunASRAPIKey: String? {
        get { getKey(key: KeychainKey.aliyunASR) }
        set { setKey(key: KeychainKey.aliyunASR, value: newValue) }
    }

    /// 阿里云 AI API Key（通义千问，可与 ASR 共用）
    var aliyunAIAPIKey: String? {
        get { getKey(key: KeychainKey.aliyunAI) }
        set { setKey(key: KeychainKey.aliyunAI, value: newValue) }
    }

    /// 用户 Auth Token（用于时光锚点等高级功能）
    var authToken: String? {
        get { getKey(key: KeychainKey.authToken) }
        set { setKey(key: KeychainKey.authToken, value: newValue) }
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Keychain Operations

    /// 保存 Key 到 Keychain
    func setKey(key: String, value: String?) {
        guard let value = value, !value.isEmpty else {
            deleteKey(key: key)
            return
        }

        let data = value.data(using: .utf8)!

        // 先删除旧的值（如果存在）
        deleteKey(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[APIKeyStore] Failed to save key \(key): \(status)")
        }
    }

    /// 从 Keychain 获取 Key
    func getKey(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// 从 Keychain 删除 Key
    func deleteKey(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// 检查是否已配置 API Key
    var hasAliyunAPIKey: Bool {
        guard let key = aliyunASRAPIKey else { return false }
        return !key.isEmpty
    }

    /// 清除所有 API Keys
    func clearAll() {
        deleteKey(key: KeychainKey.aliyunASR)
        deleteKey(key: KeychainKey.aliyunAI)
    }
}
