//
//  AppLog.swift
//  MiniTools-SwiftUI
//
//  使用系统统一日志；在 Xcode 底部 Console 搜索栏输入「子系统名」或 category 名可过滤。
//  例如：category:notifications
//

import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "MiniTools"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let widget = Logger(subsystem: subsystem, category: "widget")
}
