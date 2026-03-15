//
//  FeedbackWindowManager.swift
//  VoxLink
//
//  Manages the Feedback window
//

import AppKit
import SwiftUI

@MainActor
final class FeedbackWindowManager {
    static let shared = FeedbackWindowManager()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let feedbackView = FeedbackView()
        let hostingView = NSHostingView(rootView: feedbackView)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "帮助与反馈"
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
