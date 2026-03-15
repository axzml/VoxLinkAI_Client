//
//  UpdateService.swift
//  VoxLink
//
//  Service for checking app updates
//

import Combine
import Foundation
import SwiftUI

/// Update information from server
struct UpdateInfo: Codable {
    let latestVersion: String
    let downloadUrl: String?
    let releaseNotes: String?
    let forceUpdate: Bool

    enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case downloadUrl = "download_url"
        case releaseNotes = "release_notes"
        case forceUpdate = "force_update"
    }
}

/// Version comparison result
enum VersionComparison {
    case newer
    case same
    case older
}

/// Version struct for semantic version comparison
struct Version: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ versionString: String) {
        let components = versionString.split(separator: ".").map { Int($0) ?? 0 }
        major = components.count > 0 ? components[0] : 0
        minor = components.count > 1 ? components[1] : 0
        patch = components.count > 2 ? components[2] : 0
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    static func == (lhs: Version, rhs: Version) -> Bool {
        return lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
    }

    var description: String {
        return "\(major).\(minor).\(patch)"
    }
}

/// Service for checking app updates
@MainActor
class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var errorMessage: String?
    @Published var showUpdateAlert: Bool = false

    private let apiBaseURL: String

    private init() {
        self.apiBaseURL = SettingsStore.shared.apiBaseURL
    }

    /// Check for app updates
    func checkForUpdates() async {
        guard !isChecking else { return }

        guard !apiBaseURL.isEmpty else {
            errorMessage = "更新服务未配置，请在 Secrets.plist 中设置 API_BASE_URL"
            return
        }

        isChecking = true
        errorMessage = nil

        defer {
            Task { @MainActor in
                isChecking = false
            }
        }

        do {
            guard let url = URL(string: "\(apiBaseURL)/api/v1/version") else {
                errorMessage = "无效的 API URL"
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw UpdateError.serverError
            }

            let wrapper = try JSONDecoder().decode(VersionResponseWrapper.self, from: data)

            if wrapper.success, let info = wrapper.data {
                await MainActor.run {
                    self.latestVersion = info.latestVersion
                    self.releaseNotes = info.releaseNotes

                    if let downloadStr = info.downloadUrl,
                       let downloadUrl = URL(string: downloadStr) {
                        self.downloadURL = downloadUrl
                    }

                    // Compare versions
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    let comparison = compareVersions(current: currentVersion, latest: info.latestVersion)

                    self.updateAvailable = comparison == .newer
                    self.showUpdateAlert = self.updateAvailable
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "检查更新失败: \(error.localizedDescription)"
            }
            print("[UpdateService] Error checking for updates: \(error)")
        }
    }

    /// Compare two version strings
    private func compareVersions(current: String, latest: String) -> VersionComparison {
        let currentVer = Version(current)
        let latestVer = Version(latest)

        if currentVer < latestVer {
            return .newer
        } else if currentVer == latestVer {
            return .same
        } else {
            return .older
        }
    }

    /// Open download page in browser
    func openDownloadPage() {
        if let url = downloadURL {
            NSWorkspace.shared.open(url)
        } else {
            let baseURL = SupabaseConfig.websiteBaseURL
            if !baseURL.isEmpty, let url = URL(string: "\(baseURL)/download") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Response Models

private struct VersionResponseWrapper: Codable {
    let success: Bool
    let data: UpdateInfo?
}

// MARK: - Errors

enum UpdateError: Error, LocalizedError {
    case serverError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .serverError:
            return "服务器错误"
        case .invalidResponse:
            return "无效响应"
        }
    }
}
