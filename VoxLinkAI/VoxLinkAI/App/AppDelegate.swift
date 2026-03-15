//
//  AppDelegate.swift
//  VoxLink
//
//  应用生命周期管理
//

import AppKit
import ApplicationServices
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 禁用窗口状态恢复（防止设置窗口等自动打开）
        disableWindowStateRestoration()

        // 请求辅助功能权限
        requestAccessibilityPermissions()

        // 初始化应用设置
        SettingsStore.shared.initializeDefaults()

        // 初始化所有服务
        AppServices.shared.initializeServices()

        // 应用主题
        SettingsStore.shared.applyTheme()

        // 设置 Dock 图标行为
        if SettingsStore.shared.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }

        // 检查认证状态并显示相应窗口
        checkAuthAndShowWindow()

        // 预加载设置窗口，提升首次打开速度
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SettingsWindowManager.shared.preload()
        }

        print("[VoxLinkAI] Application launched")
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        // 应用激活时检查权限状态，如果之前没有权限现在有了，重新初始化快捷键
        checkAndReinitializeHotkeyIfNeeded()
    }

    /// 检查权限并在需要时重新初始化快捷键
    private func checkAndReinitializeHotkeyIfNeeded() {
        guard AXIsProcessTrusted() else { return }
        // 权限已授予，通知 HotkeyManager 重新初始化
        AppServices.shared.hotkeyManager.reinitialize()
    }

    /// 检查认证状态并显示相应窗口
    private func checkAuthAndShowWindow() {
        // Mock 模式：跳过认证流程，直接进入主窗口
        if SupabaseConfig.useMockData {
            print("[AppDelegate] Mock mode enabled, skipping authentication")
            MainWindowManager.shared.show()
            return
        }

        Task {
            // 尝试恢复会话
            await SupabaseService.shared.restoreSession()

            // 如果已登录，从服务器刷新最新配额（确保月度重置等同步）
            if SupabaseService.shared.isAuthenticated {
                await SupabaseService.shared.refreshProfile()
            }

            await MainActor.run {
                if SupabaseService.shared.isAuthenticated {
                    // 已登录，显示主窗口
                    MainWindowManager.shared.show()
                } else {
                    // 显示登录窗口
                    LoginWindowManager.shared.show()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[VoxLinkAI] Application terminating")
    }

    func applicationSupportsSecureRestorableState() -> Bool {
        true
    }

    /// 处理 Dock 图标点击 - 重新打开主窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // 没有可见窗口时，显示主窗口
            MainWindowManager.shared.show()
        }
        return true
    }

    // MARK: - Window Management

    /// 禁用窗口状态恢复，防止设置窗口等在启动时自动打开
    private func disableWindowStateRestoration() {
        // 方法1：关闭所有非预期的窗口（延迟执行确保窗口已创建）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.closeUnexpectedWindows()
        }

        // 方法2：删除保存的窗口状态
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            let saveStatePath = NSString(string: "~/Library/Saved Application State/\(bundleIdentifier).savedState").expandingTildeInPath
            try? FileManager.default.removeItem(atPath: saveStatePath)
        }
    }

    /// 关闭非预期的窗口（如被恢复的设置窗口）
    private func closeUnexpectedWindows() {
        let expectedWindowNames = ["MainWindow", "HistoryWindow", "SettingsWindow", "about"]

        for window in NSApp.windows {
            let windowName = window.frameAutosaveName

            // 跳过预期的窗口
            if expectedWindowNames.contains(windowName) {
                continue
            }

            // 跳过菜单栏相关的窗口
            if window.styleMask.contains(.borderless) {
                continue
            }

            // 关闭没有设置 autosave name 的窗口（通常是 Settings 窗口）
            if windowName.isEmpty {
                window.close()
                print("[VoxLinkAI] Closed unexpected window: \(window.title)")
            }
        }
    }

    // MARK: - Accessibility Permissions

    private func requestAccessibilityPermissions() {
        guard !AXIsProcessTrusted() else {
            print("[VoxLinkAI] Accessibility permissions granted")
            return
        }

        print("[VoxLinkAI] Requesting accessibility permissions...")

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // 延迟打开系统偏好设置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard !AXIsProcessTrusted(),
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            else { return }
            NSWorkspace.shared.open(url)
        }
    }
}
