//
//  WidgetURLHandler.swift
//  MiniTools-SwiftUI
//
//  小组件通过 minitools://complete?... 打开应用时完成勾选。
//

import Foundation

/// 解析小组件发来的 `minitools://complete?...` URL，在应用内勾选对应一次性 / 例行 / 时段任务。
enum WidgetURLHandler {
    private static let scheme = "minitools"

    @MainActor
    static func handle(_ url: URL, store: EfficiencyStore) async {
        guard url.scheme == scheme else { return }
        // `minitools://open`：仅由小组件 `.widgetURL` 唤起应用，无需写盘。
        guard url.host == "complete" else { return }
        let items = queryItems(url)
        guard let type = items["type"] else { return }

        switch type {
        case "onetime":
            guard let id = items["id"] else { return }
            await store.setOneTimeReminderCompleted(id: id, completed: true)
        case "recurring":
            guard let id = items["id"], let ymd = items["ymd"] else { return }
            store.setTaskCompleted(taskId: id, ymd: ymd, done: true)
        case "hourly":
            guard let id = items["id"], let ymd = items["ymd"] else { return }
            store.setHourlyWindowTaskCompleted(taskId: id, ymd: ymd, done: true)
        default:
            break
        }
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let q = c.queryItems
        else { return [:] }
        var d: [String: String] = [:]
        for i in q {
            if let v = i.value { d[i.name] = v }
        }
        return d
    }
}
