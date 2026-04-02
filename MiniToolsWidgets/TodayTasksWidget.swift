//
//  TodayTasksWidget.swift
//  MiniToolsWidgetsExtension
//

import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let rows: [TodayRowData]
    /// 已计入与 `rows` 去重后的「下次待办」数据源；界面内会再次 `loadEntry` 刷新。
    let nextUp: NextUpTaskInfo?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayEntry {
        TodayEntry(date: Date(), rows: [], nextUp: nil)
    }

    func getSnapshot(in _: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        let loaded = TodayWidgetRowLoader.loadEntry(at: now)
        completion(TodayEntry(date: now, rows: loaded.rows, nextUp: loaded.nextUp))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let loaded = TodayWidgetRowLoader.loadEntry(at: now)
        let entry = TodayEntry(date: now, rows: loaded.rows, nextUp: loaded.nextUp)
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let nextHour = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let nextMidnight = cal.date(byAdding: .day, value: 1, to: start) ?? nextHour
        let refresh = min(nextHour, nextMidnight)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct TodayTasksWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily

    var entry: TodayEntry

    private var family: WidgetFamily {
        environmentFamily
    }

    var body: some View {
        // 与 TimelineProvider 写入的 `entry` 一致；预览画布也依赖 `entry` 中的样例数据，勿在此处再 load 磁盘。
        let pack = (rows: entry.rows, nextUp: entry.nextUp)
        widgetLayout(pack: pack)
            .padding(8)
            // 未包住 `Link` 的空白、标题、行内文字等区域点击时打开 App；`Link`（圆圈、「在 App 中完成」）仍优先走完成深链。
            .widgetURL(WidgetDeepLink.openAppURL)
    }

    @ViewBuilder
    private func widgetLayout(pack: (rows: [TodayRowData], nextUp: NextUpTaskInfo?)) -> some View {
        switch family {
        case .systemSmall:
            compactVerticalLayout(pack: pack)
        case .systemMedium, .systemLarge:
            // 中大尺寸（含最大正方形）：左右分栏，避免纵向堆叠在 WidgetKit 里被裁掉下半段，导致永远只剩「今日待办」。
            twoColumnLayout(pack: pack)
        default:
            twoColumnLayout(pack: pack)
        }
    }

    /// 小尺寸：纵向排列，并限制今日高度以便挤出「下次待办」。
    private func compactVerticalLayout(pack: (rows: [TodayRowData], nextUp: NextUpTaskInfo?)) -> some View {
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

    private func twoColumnLayout(pack: (rows: [TodayRowData], nextUp: NextUpTaskInfo?)) -> some View {
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
    private func nextUpSection(pack: (rows: [TodayRowData], nextUp: NextUpTaskInfo?)) -> some View {
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

    private var sectionTitleFont: Font {
        family == .systemSmall ? .subheadline.weight(.semibold) : .headline
    }

    @ViewBuilder
    private func nextUpContent(_ next: NextUpTaskInfo) -> some View {
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
            if let url = WidgetDeepLink.completeURL(forNextUp: next) {
                Link("在 App 中完成", destination: url)
                    .font(.caption2)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func todayListContent(rows: [TodayRowData]) -> some View {
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
        case .systemSmall: return 3
        case .systemMedium: return 6
        case .systemLarge: return 12
        default: return 6
        }
    }

    @ViewBuilder
    private func rowView(_ row: TodayRowData) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let url = WidgetDeepLink.completeURL(for: row) {
                Link(destination: url) {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(row.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TodayTasksWidget: Widget {
    static let kind = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
                .containerBackground(.fill.secondary, for: .widget)
        }
        .configurationDisplayName("今日待办")
        .description("中大尺寸为左右两栏：今日待办 / 下次待办；小尺寸为上下排列。点击圆圈或「在 App 中完成」可勾选；点击其它区域打开应用。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// 预览请打开主 App 内 `TodayTasksWidgetPreviewHost.swift`（macOS 无法为 widgetExtension 跑 SwiftUI Preview）。
