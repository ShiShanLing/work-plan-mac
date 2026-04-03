//
//  TodayTasksWidgetPreviewHost.swift
//  MiniTools-SwiftUI
//
//  macOS 上 Xcode 无法为 `widgetExtension` 启动 SwiftUI Preview（“No plugin is registered…”）。
//  因此在主 App target 中用等价布局做画布调试；改 UI 时请与 `MiniToolsWidgets/TodayTasksWidget.swift` 保持同步。
//

import Foundation
import SwiftUI
import WidgetKit

// MARK: - 与扩展侧模型字段一致（本 target 内专用，避免依赖 appex 模块）

private struct PreviewTodayRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let isOneTime: Bool
    let isHourly: Bool
    let rawId: String
    let todayYmd: String
    let oneTimeHour: Int?
    let oneTimeMinute: Int?
}

private extension PreviewTodayRow {
    var todayListDisplaySubtitle: String {
        if isOneTime, let h = oneTimeHour, let m = oneTimeMinute {
            return String(format: "定时 · %02d:%02d", h, m)
        }
        return subtitle
    }
}

private struct PreviewNextUp {
    let title: String
    let detail: String
    let isOneTime: Bool
    let isHourly: Bool
    let rawId: String
    let ymdForRecurring: String
}

private struct PreviewWidgetEntry {
    let date: Date
    let rows: [PreviewTodayRow]
    let nextUp: PreviewNextUp?
}

private enum PreviewDeepLink {
    private static let scheme = "minitools"

    static func completeURL(for row: PreviewTodayRow) -> URL? {
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

    static var openAppURL: URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "open"
        return c.url!
    }
}

// MARK: - 与 TodayTasksWidgetView 同结构的预览画布

private struct TodayTasksWidgetPreviewCanvas: View {
    var previewFamily: WidgetFamily
    var entry: PreviewWidgetEntry

    private var family: WidgetFamily { previewFamily }

    private var sectionTitleFont: Font {
        family == .systemSmall ? .subheadline.weight(.semibold) : .headline
    }

    var body: some View {
        let pack = (rows: entry.rows, nextUp: entry.nextUp)
        widgetLayout(pack: pack)
            .padding(8)
    }

    @ViewBuilder
    private func widgetLayout(pack: (rows: [PreviewTodayRow], nextUp: PreviewNextUp?)) -> some View {
        switch family {
        case .systemSmall:
            compactVerticalLayout(pack: pack)
        case .systemMedium, .systemLarge:
            twoColumnLayout(pack: pack)
        default:
            twoColumnLayout(pack: pack)
        }
    }

    private func compactVerticalLayout(pack: (rows: [PreviewTodayRow], nextUp: PreviewNextUp?)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日待办")
                .font(sectionTitleFont)
                .foregroundStyle(.primary)
            Group {
                if pack.rows.isEmpty {
                    Text("今日无待办事项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    todayListContent(rows: pack.rows)
                }
            }
            .frame(maxHeight: 110, alignment: .topLeading)
            .clipped()

            Divider()
                .padding(.vertical, 2)

            nextUpSection(pack: pack)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func twoColumnLayout(pack: (rows: [PreviewTodayRow], nextUp: PreviewNextUp?)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今日待办")
                    .font(sectionTitleFont)
                    .foregroundStyle(.primary)
                if pack.rows.isEmpty {
                    Text("今日无待办事项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    todayListContent(rows: pack.rows)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(.secondary.opacity(0.35))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            nextUpSection(pack: pack)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func nextUpSection(pack: (rows: [PreviewTodayRow], nextUp: PreviewNextUp?)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("下次待办")
                .font(sectionTitleFont)
                .foregroundStyle(.primary)
            if let next = pack.nextUp {
                nextUpContent(next)
            } else {
                Text("没其他任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private func nextUpContent(_ next: PreviewNextUp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(next.title)
                .font(family == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(family == .systemSmall ? 4 : 3)
                .minimumScaleFactor(0.85)
            Text(next.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 4 : 5)
            Link("在 App 中查看", destination: PreviewDeepLink.openAppURL)
                .font(.caption2)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func todayListContent(rows: [PreviewTodayRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let maxRows = rowLimit
            let shown = Array(rows.prefix(maxRows))
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                rowView(row)
                if index < shown.count - 1 {
                    Divider()
                        .padding(.vertical, 4)
                }
            }
            if rows.count > maxRows {
                Text("还有 \(rows.count - maxRows) 项…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        case .systemLarge: return 4
        default: return 2
        }
    }

    @ViewBuilder
    private func rowView(_ row: PreviewTodayRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let url = PreviewDeepLink.completeURL(for: row) {
                Link(destination: url) {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(row.todayListDisplaySubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 样例数据与 #Preview

private enum TodayTasksWidgetPreviewData {
    static let ymd = "2026-03-31"
    static let rows: [PreviewTodayRow] = [
        PreviewTodayRow(id: "o-1", title: "买牛奶", subtitle: "定时 · 09:30", isOneTime: true, isHourly: false, rawId: "preview-onetime", todayYmd: ymd, oneTimeHour: 9, oneTimeMinute: 30),
        PreviewTodayRow(id: "r-1", title: "团队例会", subtitle: "例行 · 每周一", isOneTime: false, isHourly: false, rawId: "preview-recurring", todayYmd: ymd, oneTimeHour: nil, oneTimeMinute: nil),
        PreviewTodayRow(id: "h-1", title: "喝水", subtitle: "时段 · 每 1 小时 · 09:00–17:30 · 仅工作日", isOneTime: false, isHourly: true, rawId: "preview-hourly", todayYmd: ymd, oneTimeHour: nil, oneTimeMinute: nil),
    ]
    static let nextUp = PreviewNextUp(
        title: "交周报",
        detail: "2026-04-01 周三 · 提醒 10:00 · 每周三",
        isOneTime: false,
        isHourly: false,
        rawId: "preview-next",
        ymdForRecurring: "2026-04-01"
    )

    static var entryFull: PreviewWidgetEntry {
        PreviewWidgetEntry(date: Date(), rows: rows, nextUp: nextUp)
    }

    static var entryEmptyToday: PreviewWidgetEntry {
        PreviewWidgetEntry(date: Date(), rows: [], nextUp: nextUp)
    }
}

#Preview("小组件 · 大尺寸两栏") {
    TodayTasksWidgetPreviewCanvas(previewFamily: .systemLarge, entry: TodayTasksWidgetPreviewData.entryFull)
        .frame(width: 360, height: 380)
        .containerBackground(.fill.secondary, for: .widget)
}

#Preview("小组件 · 小尺寸上下") {
    TodayTasksWidgetPreviewCanvas(previewFamily: .systemSmall, entry: TodayTasksWidgetPreviewData.entryEmptyToday)
        .frame(width: 170, height: 170)
        .containerBackground(.fill.secondary, for: .widget)
}
