//
//  AppGroup.swift
//  MiniTools-SwiftUI
//

import Foundation

/// 主应用与小组件共享容器（须在 Xcode 能力中勾选同一 App Group，并与开发者后台一致）。
/// JSON 实际路径为 `Group Container / MiniToolsData/*.json`（主应用与小组件共用）。
enum AppGroup {
    static let identifier = "group.com.MiniTools.www.MiniTools-SwiftUI"
}
