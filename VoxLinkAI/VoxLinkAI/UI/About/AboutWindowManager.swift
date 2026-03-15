//
//  AboutWindowManager.swift
//  VoxLink
//
//  Manages the About window
//

import AppKit
import SwiftUI

@MainActor
final class AboutWindowManager {
    static let shared = AboutWindowManager()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let hostingView = NSHostingView(rootView: aboutView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "关于 VoxLink AI"
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
