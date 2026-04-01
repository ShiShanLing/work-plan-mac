//
//  MiniToolsDataIsolation.swift
//  MiniToolsCore
//

import Foundation

/// App Group 内统一使用同一子目录名，保证 **Xcode Debug 运行**、**从桌面/启动台打开的安装版**、**小组件扩展**读写同一套 JSON。
/// （历史上 Debug 曾使用 `MiniToolsData-debug`，已在 `LocalJSONStore` 做一次性迁回 `MiniToolsData`。）
public enum MiniToolsDataIsolation {
    public static let appGroupJSONDirectoryName = "MiniToolsData"
}
