//
//  MiniToolsDataIsolation.swift
//  MiniToolsCore
//

import Foundation

/// App Group 内存放 JSON 的目录名：Debug 与 Release 分开，避免本机 Xcode 运行读写到与正式安装同一套文件。
public enum MiniToolsDataIsolation {
    public static var appGroupJSONDirectoryName: String {
        #if DEBUG
        "MiniToolsData-debug"
        #else
        "MiniToolsData"
        #endif
    }
}
