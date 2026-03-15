//
//  LoginWindowManager.swift
//  VoxLink
//
//  登录窗口管理器
//

import AppKit
import Combine
import SwiftUI

/// 登录窗口管理器
class LoginWindowManager: NSObject, ObservableObject {
    static let shared = LoginWindowManager()

    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()

        // 监听认证状态变化
        SupabaseService.shared.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthenticated in
                if isAuthenticated {
                    self?.close()
                    // 登录成功后显示主窗口
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        MainWindowManager.shared.show()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// 显示登录窗口
    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let loginView = LoginView()
        let hostingView = NSHostingView(rootView: loginView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "VoxLink AI"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        // 现代化窗口样式
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.backgroundColor = NSColor.windowBackgroundColor

        // 移除标题栏分隔线
        newWindow.toolbarStyle = .unifiedCompact

        // 设置窗口层级
        newWindow.level = .floating

        window = newWindow
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("[LoginWindowManager] Login window shown")
    }

    /// 关闭登录窗口
    func close() {
        guard let window = window else { return }

        // 添加淡出动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
            self.window = nil
        })

        print("[LoginWindowManager] Login window closed")
    }
}

// MARK: - NSWindowDelegate

extension LoginWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 如果用户关闭窗口但未登录，退出应用
        if !SupabaseService.shared.isAuthenticated {
            NSApp.terminate(nil)
        }
    }
}
