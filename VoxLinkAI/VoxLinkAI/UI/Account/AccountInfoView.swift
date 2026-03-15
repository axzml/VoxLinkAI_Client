//
//  AccountInfoView.swift
//  VoxLink
//
//  Account information view showing email, user ID, and avatar upload
//

import Supabase
import SwiftUI
import UniformTypeIdentifiers

struct AccountInfoView: View {
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var quotaService = QuotaService.shared
    @State private var isUploadingAvatar = false
    @State private var showSuccessMessage = false
    @State private var errorMessage: String?

    private var userEmail: String {
        supabaseService.userEmail ?? "未知"
    }

    private var userId: String {
        supabaseService.currentUser?.id.uuidString ?? "未知"
    }

    private var userLevel: UserLevel {
        supabaseService.userProfile?.userLevel ?? .free
    }

    private var currentModeText: String {
        quotaService.currentUsage?.currentModeText ?? "🔑 未配置 Key"
    }

    private var currentModeColor: Color {
        quotaService.currentUsage?.currentModeColor ?? .orange
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("账户信息")
                .font(.system(size: 18, weight: .semibold))

            // Avatar section
            VStack(spacing: 12) {
                AvatarView(email: userEmail, avatarUrl: nil, size: 80)

                Button(action: uploadAvatar) {
                    HStack(spacing: 6) {
                        if isUploadingAvatar {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "camera")
                                .font(.system(size: 12))
                        }
                        Text("更换头像")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isUploadingAvatar)
            }

            // Service Mode Badge
            HStack(spacing: 8) {
                Text(currentModeText)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(currentModeColor.opacity(0.15))
                    .foregroundColor(currentModeColor)
                    .cornerRadius(8)
            }

            // Info section
            VStack(alignment: .leading, spacing: 16) {
                infoRow(label: "邮箱", value: userEmail)
                infoRow(label: "用户 ID", value: userId)
                infoRow(label: "账户等级", value: userLevel.displayName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            // Success/Error message
            if showSuccessMessage {
                Text("头像已更新")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
        }
        .padding(24)
        .frame(width: 320, height: 380)
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
    }

    private func uploadAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isUploadingAvatar = true
        errorMessage = nil

        Task {
            do {
                // Load image
                guard let imageData = try? Data(contentsOf: url),
                      let image = NSImage(data: imageData) else {
                    await MainActor.run {
                        errorMessage = "无法加载图片"
                        isUploadingAvatar = false
                    }
                    return
                }

                // Resize image to reasonable size
                let resizedImage = resizeImage(image, maxSize: 200)
                guard let pngData = resizedImage.pngData() else {
                    await MainActor.run {
                        errorMessage = "无法处理图片"
                        isUploadingAvatar = false
                    }
                    return
                }

                // Save to local storage
                let fileName = "avatar_\(userId).png"
                let saveURL = getAvatarsDirectory().appendingPathComponent(fileName)

                try pngData.write(to: saveURL)

                // Update settings
                await MainActor.run {
                    SettingsStore.shared.localAvatarPath = saveURL.path
                    showSuccessMessage = true
                    isUploadingAvatar = false

                    // Hide success message after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSuccessMessage = false
                    }
                }

                print("[AccountInfoView] Avatar saved to: \(saveURL.path)")
            } catch {
                await MainActor.run {
                    errorMessage = "保存头像失败: \(error.localizedDescription)"
                    isUploadingAvatar = false
                }
            }
        }
    }

    private func resizeImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let ratio = min(maxSize / image.size.width, maxSize / image.size.height)
        let newSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        newImage.unlockFocus()
        return newImage
    }

    private func getAvatarsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let avatarsDir = appSupport.appendingPathComponent("VoxLinkAI/Avatars")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: avatarsDir, withIntermediateDirectories: true)

        return avatarsDir
    }
}

// MARK: - NSImage Extension

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - Preview

#Preview {
    AccountInfoView()
}
