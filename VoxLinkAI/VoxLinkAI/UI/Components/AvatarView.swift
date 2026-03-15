//
//  AvatarView.swift
//  VoxLink
//
//  Avatar component - displays user avatar or email initial
//

import SwiftUI

/// Avatar view that displays user avatar image or email initial with hash-based background color
struct AvatarView: View {
    let email: String
    let avatarUrl: String?
    let size: CGFloat

    /// Background color based on email hash
    private var backgroundColor: Color {
        avatarColor(for: email)
    }

    /// Initial letter to display (first character of email)
    private var initial: String {
        let firstChar = email.uppercased().first ?? "?"
        return String(firstChar)
    }

    var body: some View {
        Group {
            if let urlString = avatarUrl, let url = URL(string: urlString) {
                // Load remote avatar image
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        // Fallback to initial on load failure
                        initialView
                    case .empty:
                        // Show placeholder while loading
                        ProgressView()
                            .scaleEffect(0.5)
                    @unknown default:
                        initialView
                    }
                }
            } else if let localPath = getLocalAvatarPath(), let nsImage = NSImage(contentsOfFile: localPath) {
                // Load local avatar image
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Show initial
                initialView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// View showing the initial letter
    private var initialView: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(initial)
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    /// Get local avatar path from settings
    private func getLocalAvatarPath() -> String? {
        return SettingsStore.shared.localAvatarPath
    }

    /// Generate a consistent color based on email hash
    private func avatarColor(for email: String) -> Color {
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange, .yellow,
            .green, .mint, .teal, .cyan, .indigo
        ]

        // Simple hash function
        var hash = 0
        for char in email.unicodeScalars {
            hash = Int(hash &* 31 &+ Int(char.value))
        }

        let index = abs(hash) % colors.count
        return colors[index]
    }
}

// MARK: - Preview

#Preview("Avatar with Initial") {
    HStack(spacing: 16) {
        AvatarView(email: "alice@example.com", avatarUrl: nil, size: 40)
        AvatarView(email: "bob@example.com", avatarUrl: nil, size: 32)
        AvatarView(email: "charlie@example.com", avatarUrl: nil, size: 24)
    }
    .padding()
}
