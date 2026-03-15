//
//  VoxLinkApp.swift
//  VoxLink
//
//  Swift 原生语音输入助手
//

import AppKit
import SwiftUI

@main
struct VoxLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appServices = AppServices.shared
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        // 使用 Settings 场景（不会自动显示窗口）
        // 所有窗口由各自的 Manager 手动管理
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }

            // 替换设置命令，使用自定义的 SettingsWindowManager
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    SettingsWindowManager.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("VoxLink AI") {
                Button("开始录音") {
                    Task { await appServices.asrService.toggleRecording() }
                }
                .keyboardShortcut("R", modifiers: .command)

                Divider()

                Button("显示主窗口") {
                    MainWindowManager.shared.show()
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("历史记录") {
                    HistoryWindowManager.shared.show()
                }
                .keyboardShortcut("2", modifiers: .command)
            }
        }
    }
}

// 空视图
struct EmptyView: View {
    var body: some View {
        Color.clear
    }
}
