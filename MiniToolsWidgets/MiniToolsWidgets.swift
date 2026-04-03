//
//  MiniToolsWidgets.swift
//  MiniToolsWidgetsExtension
//

import SwiftUI
import WidgetKit

/// 小组件扩展入口：当前仅注册「今日待办」`TodayTasksWidget`。
@main
struct MiniToolsWidgets: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
    }
}
