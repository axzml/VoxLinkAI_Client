//
//  AccountInfoWindowManager.swift
//  VoxLink
//
//  Manages the Account Info window
//

import AppKit
import SwiftUI

@MainActor
final class AccountInfoWindowManager {
    static let shared = AccountInfoWindowManager()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let accountView = AccountInfoView()
        let hostingView = NSHostingView(rootView: accountView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "账户信息"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    func close() {
        window?.close()
    }
}
