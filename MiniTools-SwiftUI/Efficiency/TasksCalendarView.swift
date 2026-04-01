//
//  TasksCalendarView.swift
//  MiniTools-SwiftUI
//
//  月历汇总「定时提醒」「例行任务」在每一天的分布（不含「时段提醒」；类似 Outlook 月视图在格子里看到事项）。
//

import AppKit
import SwiftUI

// MARK: - 模型

/// 月历与「某日」弹层共用：默认展示未完成，可切换为仅查看已完成。
private enum CalendarTaskCompletionFilter: String, CaseIterable, Identifiable {
    case incomplete
    case completed

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .incomplete: return "未完成"
        case .completed: return "已完成"
        }
    }
}

private struct CalendarTaskRow: Identifiable {
    enum Kind: String {
        case oneTime = "定时"
        case recurring = "例行"
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    var isCompleted: Bool
    /// 一次性 / 例行 任务 id
    let rawId: String
    let isOneTime: Bool
}

private enum MonthGridCell: Identifiable {
    case padding(Int)
    case day(ymd: String, dayNumber: Int)

    var id: String {
        switch self {
        case let .padding(i): return "p-\(i)"
        case let .day(ymd, _): return ymd
        }
    }
}

/// 用于 `.sheet(item:)` 弹出某一天的任务列表。
private struct CalendarSheetDay: Identifiable {
    let ymd: String
    var id: String { ymd }
}

private enum TasksCalendarLogic {
    static func monthGrid(for monthContaining: Date, calendar cal: Calendar) -> [MonthGridCell] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthContaining)),
              let dayRange = cal.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let firstWeekday = cal.component(.weekday, from: monthStart)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var cells: [MonthGridCell] = []
        var pad = 0
        for _ in 0 ..< leading {
            cells.append(.padding(pad))
            pad += 1
        }
        for d in dayRange {
            var comps = cal.dateComponents([.year, .month], from: monthStart)
            comps.day = d
            guard let date = cal.date(from: comps) else { continue }
            let ymd = LocalCalendarDate.localYmd(date, calendar: cal)
            cells.append(.day(ymd: ymd, dayNumber: d))
        }
        while cells.count % 7 != 0 {
            cells.append(.padding(pad))
            pad += 1
        }
        return cells
    }

    static func tasks(
        on ymd: String,
        store: EfficiencyStore,
        calendar cal: Calendar,
        filter: CalendarTaskCompletionFilter
    ) -> [CalendarTaskRow] {
        guard let dayDate = LocalCalendarDate.parseLocalYmd(ymd, calendar: cal) else { return [] }
        var rows: [CalendarTaskRow] = []

        let oneTimes = store.oneTimeReminders
            .filter { o in
                guard o.dateYmd == ymd else { return false }
                switch filter {
                case .incomplete: return !o.isCompleted
                case .completed: return o.isCompleted
                }
            }
            .sorted {
                if $0.hour != $1.hour { return $0.hour < $1.hour }
                return $0.minute < $1.minute
            }
        for o in oneTimes {
            let title = o.title.isEmpty ? "（无标题）" : o.title
            rows.append(CalendarTaskRow(
                id: "o-\(o.id)",
                kind: .oneTime,
                title: title,
                detail: String(format: "%02d:%02d", o.hour, o.minute),
                isCompleted: o.isCompleted,
                rawId: o.id,
                isOneTime: true
            ))
        }

        let recs = store.recurringTasks
            .filter { t in
                guard LocalCalendarDate.isTaskDueOn(recurrence: t.recurrence, ref: dayDate, calendar: cal) else { return false }
                let done = t.isCompleted(on: ymd)
                switch filter {
                case .incomplete: return !done
                case .completed: return done
                }
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        for t in recs {
            let title = t.title.isEmpty ? "（无标题）" : t.title
            let done = t.isCompleted(on: ymd)
            let timeStr = String(format: "%02d:%02d", t.notifyHour, t.notifyMinute)
            rows.append(CalendarTaskRow(
                id: "r-\(t.id)-\(ymd)",
                kind: .recurring,
                title: title,
                detail: t.notifyEnabled ? "提醒 \(timeStr)" : "无时间提醒",
                isCompleted: done,
                rawId: t.id,
                isOneTime: false
            ))
        }

        return rows
    }

    /// 月历与详情行左侧竖线：未完成用饱和色，已用柔和色，仍区分定时 / 例行。
    static func taskBarFill(kind: CalendarTaskRow.Kind, isCompleted: Bool) -> Color {
        switch kind {
        case .oneTime:
            return isCompleted
                ? Color(red: 0.52, green: 0.6, blue: 0.74)
                : Color.blue
        case .recurring:
            return isCompleted
                ? Color(red: 0.46, green: 0.64, blue: 0.52)
                : Color.green
        }
    }
}

// MARK: - 视图

struct TasksCalendarView: View {
    @Environment(EfficiencyStore.self) private var store

    @State private var monthContaining: Date = Date()
    @State private var sheetDay: CalendarSheetDay?
    @State private var taskCompletionFilter: CalendarTaskCompletionFilter = .incomplete

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh-Hans")
        cal.timeZone = .current
        return cal
    }

    private var monthTitle: String {
        let y = calendar.component(.year, from: monthContaining)
        let m = calendar.component(.month, from: monthContaining)
        return String(format: "%d 年 %d 月", y, m)
    }

    private var grid: [MonthGridCell] {
        TasksCalendarLogic.monthGrid(for: monthContaining, calendar: calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthChrome
            weekdayHeader
            calendarGrid
            Text("使用上方「未完成 / 已完成」切换月历与当日列表。点击日期打开详情；未完成模式下可勾选并添加「定时提醒」。例行任务在「例行任务」页管理；时段提醒不在日历中展示。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .navigationTitle("日历")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $sheetDay) { item in
            CalendarDayTasksSheet(ymd: item.ymd, calendar: calendar, store: store, completionFilter: taskCompletionFilter)
        }
    }

    private var monthChrome: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(monthTitle)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 160)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)

            Spacer()

            Picker("事项状态", selection: $taskCompletionFilter) {
                ForEach(CalendarTaskCompletionFilter.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 200)

            Button("本月") {
                monthContaining = Date()
                sheetDay = nil
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var weekdayHeader: some View {
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        return HStack(spacing: 0) {
            ForEach(0 ..< 7, id: \.self) { i in
                Text(labels[i])
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var calendarGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
        return LazyVGrid(columns: cols, spacing: 1) {
            ForEach(grid) { cell in
                switch cell {
                case .padding:
                    Color.clear
                        .aspectRatio(1.15, contentMode: .fit)
                case let .day(ymd, dayNumber):
                    dayCell(ymd: ymd, dayNumber: dayNumber)
                }
            }
        }
        .padding(.horizontal, 8)
        .background(Color(nsColor: .separatorColor).opacity(0.35))
    }

    private func dayCell(ymd: String, dayNumber: Int) -> some View {
        let tasks = TasksCalendarLogic.tasks(on: ymd, store: store, calendar: calendar, filter: taskCompletionFilter)
        let isToday = ymd == LocalCalendarDate.localYmd(Date(), calendar: calendar)
        let hasTasks = !tasks.isEmpty
        let cellFill = cellBackground(hasTasks: hasTasks)

        return Button {
            sheetDay = CalendarSheetDay(ymd: ymd)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(dayNumber)")
                        .font(.subheadline.weight(isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 2)

                ForEach(Array(tasks.prefix(3).enumerated()), id: \.element.id) { _, row in
                    HStack(alignment: .center, spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(TasksCalendarLogic.taskBarFill(kind: row.kind, isCompleted: row.isCompleted))
                            .frame(width: 3, height: 12)
                        Text(row.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(row.isCompleted ? .tertiary : .primary)
                            .strikethrough(row.isCompleted)
                    }
                }
                if tasks.count > 3 {
                    Text("+\(tasks.count - 3)…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isToday ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 有事项的日期：柔和强调底色；今天再叠一层浅描边（见 overlay）。
    private func cellBackground(hasTasks: Bool) -> Color {
        if hasTasks {
            return Color.accentColor.opacity(0.14)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthContaining) else { return }
        monthContaining = next
        sheetDay = nil
    }
}

// MARK: - 弹出层：某日全部任务

private struct CalendarDayTasksSheet: View {
    @Environment(\.dismiss) private var dismiss

    let ymd: String
    let calendar: Calendar
    let store: EfficiencyStore
    let completionFilter: CalendarTaskCompletionFilter

    @State private var newOneTimeDraft: OneTimeReminder?

    private var list: [CalendarTaskRow] {
        TasksCalendarLogic.tasks(on: ymd, store: store, calendar: calendar, filter: completionFilter)
    }

    var body: some View {
        NavigationStack {
            Group {
                if list.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            emptySheetTitle,
                            systemImage: "calendar",
                            description: Text(emptySheetDescription)
                        )
                        if completionFilter == .incomplete {
                            Button {
                                openAddOneTime()
                            } label: {
                                Label("添加定时提醒", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(list) { row in
                                dayDetailRow(row, ymd: ymd)
                            }
                            if completionFilter == .incomplete {
                                Button {
                                    openAddOneTime()
                                } label: {
                                    Label("添加定时提醒", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(formattedDayHeader(ymd))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .sheet(item: $newOneTimeDraft) { draft in
            OneTimeReminderEditSheet(store: store, reminder: draft, isNew: true, lockDateYmd: ymd)
        }
    }

    private var emptySheetTitle: String {
        switch completionFilter {
        case .incomplete: return "当天暂无未完成事项"
        case .completed: return "当天暂无已完成事项"
        }
    }

    private var emptySheetDescription: String {
        switch completionFilter {
        case .incomplete:
            return "可添加定时提醒；例行任务请在「例行任务」中创建。时段提醒仅出现在「时段提醒」页与小组件。"
        case .completed:
            return "在「未完成」模式下勾选后，完成记录会出现在这里。也可切回月历查看其它日期。"
        }
    }

    private func openAddOneTime() {
        newOneTimeDraft = OneTimeReminder.newDraftForCalendarDay(ymd: ymd, calendar: calendar)
    }

    private func formattedDayHeader(_ ymd: String) -> String {
        guard let d = LocalCalendarDate.parseLocalYmd(ymd, calendar: calendar) else { return ymd }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh-Hans")
        df.dateFormat = "yyyy-MM-dd EEEE"
        return df.string(from: d)
    }

    private func dayDetailRowLiveCompleted(_ row: CalendarTaskRow, ymd: String) -> Bool {
        if row.isOneTime {
            return store.oneTimeReminders.first(where: { $0.id == row.rawId })?.isCompleted ?? false
        }
        return store.recurringTasks.first(where: { $0.id == row.rawId })?.isCompleted(on: ymd) ?? false
    }

    private func dayDetailRow(_ row: CalendarTaskRow, ymd: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(TasksCalendarLogic.taskBarFill(kind: row.kind, isCompleted: dayDetailRowLiveCompleted(row, ymd: ymd)))
                .frame(width: 4, height: 40)
                .accessibilityHidden(true)
            Toggle(isOn: Binding(
                get: {
                    dayDetailRowLiveCompleted(row, ymd: ymd)
                },
                set: { v in
                    if row.isOneTime {
                        Task { @MainActor in
                            await store.setOneTimeReminderCompleted(id: row.rawId, completed: v)
                        }
                    } else {
                        store.setTaskCompleted(taskId: row.rawId, ymd: ymd, done: v)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.kind.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        Text(row.title)
                            .font(.subheadline.weight(.medium))
                    }
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

#Preview {
    NavigationStack {
        TasksCalendarView()
            .environment(EfficiencyStore())
    }
}
