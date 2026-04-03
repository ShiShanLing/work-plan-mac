//
//  WidgetReloader.swift
//  MiniTools-SwiftUI
//

import Foundation
import WidgetKit

/// 数据变更后主进程调用，刷新所有 Widget 时间线。
enum MiniToolsWidgetReloader {
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
