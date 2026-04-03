//
//  SystemSettings.swift
//  MiniTools-SwiftUI
//

#if os(macOS)
import AppKit

/// 打开系统设置中的通知偏好页面（macOS）。
enum SystemSettings {
    static func openNotificationsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
