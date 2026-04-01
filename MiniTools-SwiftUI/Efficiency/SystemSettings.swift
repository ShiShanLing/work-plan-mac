//
//  SystemSettings.swift
//  MiniTools-SwiftUI
//

#if os(macOS)
import AppKit

enum SystemSettings {
    static func openNotificationsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
