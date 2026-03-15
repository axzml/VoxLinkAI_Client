//
//  MenuBarManager.swift
//  VoxLink
//
//  菜单栏图标和菜单管理
//

import AppKit
import Combine
import SwiftUI

/// 菜单栏管理器
@MainActor
final class MenuBarManager: ObservableObject {
    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private weak var asrService: ASRService?
    private var cancellables = Set<AnyCancellable>()

    @Published var isRecording: Bool = false

    // MARK: - Initialization

    init() {
        setupStatusItem()
        // 延迟配置，避免初始化循环
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            self.configure(asrService: AppServices.shared.asrService)
        }
    }

    // MARK: - Configuration

    func configure(asrService: ASRService) {
        self.asrService = asrService

        // 订阅录音状态
        asrService.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRunning in
                self?.isRecording = isRunning
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        // 设置初始图标
        updateStatusItem()

        // 创建菜单
        let menu = createMenu()
        statusItem.menu = menu
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if isRecording {
            // 录音中 - 显示红点
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button.imagePosition = .imageLeading
            button.title = ""
            button.contentTintColor = .systemRed
        } else {
            // 空闲 - 显示白色圆圈图标
            if let icon = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "VoxLink") {
                let whiteIcon = NSImage(size: icon.size)
                whiteIcon.lockFocus()
                NSColor.white.set()
                let imageRect = NSRect(origin: .zero, size: icon.size)
                icon.draw(in: imageRect)
                imageRect.fill(using: .sourceAtop)
                whiteIcon.unlockFocus()
                button.image = whiteIcon
            }
            button.imagePosition = .imageOnly
            button.title = ""
        }
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        // 短时录音
        let shortRecordItem = NSMenuItem(
            title: "短时录音",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        shortRecordItem.target = self
        menu.addItem(shortRecordItem)

        // 持续录音
        let longRecordItem = NSMenuItem(
            title: "持续录音",
            action: #selector(openLongRecording),
            keyEquivalent: ""
        )
        longRecordItem.target = self
        menu.addItem(longRecordItem)

        menu.addItem(NSMenuItem.separator())

        // 显示主窗口
        let mainWindowItem = NSMenuItem(
            title: "显示主窗口",
            action: #selector(showMainWindow),
            keyEquivalent: "1"
        )
        mainWindowItem.target = self
        menu.addItem(mainWindowItem)

        // 历史记录
        let historyItem = NSMenuItem(
            title: "历史记录",
            action: #selector(openHistory),
            keyEquivalent: "2"
        )
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        // 关于
        let aboutItem = NSMenuItem(
            title: "关于 VoxLink AI",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(
            title: "退出 VoxLink AI",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func toggleRecording() {
        Task {
            await asrService?.toggleRecording()
        }
    }

    @objc private func openLongRecording() {
        // 发送通知，让主窗口导航到长时录音页面
        NotificationCenter.default.post(name: .navigateToLongRecording, object: nil)
        MainWindowManager.shared.show()
    }

    @objc private func showMainWindow() {
        MainWindowManager.shared.show()
    }

    @objc private func openHistory() {
        HistoryWindowManager.shared.show()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToLongRecording = Notification.Name("navigateToLongRecording")
}
