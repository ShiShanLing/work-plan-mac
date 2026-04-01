//
//  AppGroup.swift
//  MiniTools-SwiftUI
//

import Foundation

/// 主应用与小组件共享容器（须在 Xcode 能力中勾选同一 App Group，并与开发者后台一致）。
/// JSON 实际路径为 `容器 / MiniToolsDataIsolation.appGroupJSONDirectoryName / *.json`（Debug 为 `MiniToolsData-debug`）。
enum AppGroup {
    static let identifier = "group.com.MiniTools.www.MiniTools-SwiftUI"
}
