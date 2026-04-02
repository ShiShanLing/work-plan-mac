//
//  WidgetDeepLink.swift
//  MiniToolsWidgetsExtension
//

import Foundation

/// 与主应用 `WidgetURLHandler` 使用相同约定；点击后由主应用处理并完成勾选。
enum WidgetDeepLink {
    private static let scheme = "minitools"

    /// 仅唤起主应用（不勾选）；用在 `.widgetURL`，使点心圆圈 / `Link` 以外区域也能点进 App。
    static var openAppURL: URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "open"
        return c.url!
    }

    static func completeURL(for row: TodayRowData) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "complete"
        if row.isOneTime {
            c.queryItems = [
                URLQueryItem(name: "type", value: "onetime"),
                URLQueryItem(name: "id", value: row.rawId),
            ]
        } else if row.isHourly {
            c.queryItems = [
                URLQueryItem(name: "type", value: "hourly"),
                URLQueryItem(name: "id", value: row.rawId),
                URLQueryItem(name: "ymd", value: row.todayYmd),
            ]
        } else {
            c.queryItems = [
                URLQueryItem(name: "type", value: "recurring"),
                URLQueryItem(name: "id", value: row.rawId),
                URLQueryItem(name: "ymd", value: row.todayYmd),
            ]
        }
        return c.url
    }

    static func completeURL(forNextUp info: NextUpTaskInfo) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "complete"
        if info.isOneTime {
            c.queryItems = [
                URLQueryItem(name: "type", value: "onetime"),
                URLQueryItem(name: "id", value: info.rawId),
            ]
        } else if info.isHourly {
            c.queryItems = [
                URLQueryItem(name: "type", value: "hourly"),
                URLQueryItem(name: "id", value: info.rawId),
                URLQueryItem(name: "ymd", value: info.ymdForRecurring),
            ]
        } else {
            c.queryItems = [
                URLQueryItem(name: "type", value: "recurring"),
                URLQueryItem(name: "id", value: info.rawId),
                URLQueryItem(name: "ymd", value: info.ymdForRecurring),
            ]
        }
        return c.url
    }
}
