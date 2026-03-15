//
//  UserMenuView.swift
//  VoxLink
//
//  User menu popup with glass morphism effect
//

import SwiftUI

/// User menu popup view with glass morphism background
struct UserMenuView: View {
    let userEmail: String?
    let userId: String?
    let avatarUrl: String?

    // Menu item actions
    let onAccountInfo: () -> Void
    let onSettings: () -> Void
    let onWebsite: () -> Void
    let onCheckUpdate: () -> Void
    let onFeedback: () -> Void
    let onAbout: () -> Void
    let onLogout: () -> Void

    @State private var isCheckingUpdate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section 1: Account info and Settings
            menuSection {
                menuItem(icon: "person.circle", title: "账户信息", action: onAccountInfo)
                menuDivider()
                menuItem(icon: "gearshape", title: "设置", action: onSettings)
            }

            menuSeparator()

            // Section 2: Website, Update, Feedback, About
            menuSection {
                menuItem(icon: "globe", title: "VoxLink AI 官网", action: onWebsite)
                menuDivider()
                menuItem(
                    icon: "arrow.triangle.2.circlepath",
                    title: "检查更新",
                    isLoading: isCheckingUpdate,
                    action: {
                        isCheckingUpdate = true
                        onCheckUpdate()
                        // Reset after a delay (actual update check will handle this)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            isCheckingUpdate = false
                        }
                    }
                )
                menuDivider()
                menuItem(icon: "questionmark.circle", title: "帮助与反馈", action: onFeedback)
                menuDivider()
                menuItem(icon: "info.circle", title: "关于", action: onAbout)
            }

            menuSeparator()

            // Section 3: Logout
            menuSection {
                menuItem(icon: "rectangle.portrait.and.arrow.right", title: "退出登录", isDestructive: true, action: onLogout)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    // MARK: - View Builders

    @ViewBuilder
    private func menuSection(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
    }

    @ViewBuilder
    private func menuItem(
        icon: String,
        title: String,
        isLoading: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(.system(size: 13))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isDestructive ? .red : .primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0))
        )
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private func menuDivider() -> some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func menuSeparator() -> some View {
        Divider()
            .padding(.vertical, 4)
    }
}

// MARK: - Account Bar View

/// Account bar view to be placed in sidebar
struct AccountBarView: View {
    let userEmail: String?
    let userId: String?
    let avatarUrl: String?
    let onMenuToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onMenuToggle) {
            HStack(spacing: 10) {
                // Avatar
                if let email = userEmail {
                    AvatarView(email: email, avatarUrl: avatarUrl, size: 28)
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                }

                // Email
                Text(userEmail ?? "未登录")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Dropdown indicator
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview("User Menu") {
    UserMenuView(
        userEmail: "user@example.com",
        userId: "123e4567-e89b-12d3-a456-426614174000",
        avatarUrl: nil,
        onAccountInfo: {},
        onSettings: {},
        onWebsite: {},
        onCheckUpdate: {},
        onFeedback: {},
        onAbout: {},
        onLogout: {}
    )
    .frame(width: 220)
}

#Preview("Account Bar") {
    VStack {
        Spacer()
        AccountBarView(
            userEmail: "user@example.com",
            userId: "123e4567-e89b-12d3-a456-426614174000",
            avatarUrl: nil,
            onMenuToggle: {}
        )
        .background(Color(nsColor: .controlBackgroundColor))
    }
    .frame(width: 200, height: 100)
}
