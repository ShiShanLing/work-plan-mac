//
//  TasksCalendarView.swift
//  MiniTools-SwiftUI
//
//  月历汇总「定时提醒」「例行任务」在每一天的分布（不含「时段提醒」；类似 Outlook 月视图在格子里看到事项）。
//

import AppKit
import SwiftUI

// MARK: - 模型

private struct CalendarTaskRow: Identifiable, Equatable {
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

    /// 单日全部「定时 + 例行」（已完成与未完成一起展示）：未完成在前，已完成在后；勾选后仍留在列表中，仅样式变为已完成。
    static func tasks(on ymd: String, store: EfficiencyStore, calendar cal: Calendar) -> [CalendarTaskRow] {
        guard let dayDate = LocalCalendarDate.parseLocalYmd(ymd, calendar: cal) else { return [] }

        let oneSorted = store.oneTimeReminders
            .filter { $0.dateYmd == ymd }
            .sorted {
                if $0.hour != $1.hour { return $0.hour < $1.hour }
                return $0.minute < $1.minute
            }
        let oneInc = oneSorted.filter { !$0.isCompleted }
        let oneDone = oneSorted.filter(\.isCompleted)

        let now = Date()
        let recSorted = store.recurringTasks
            .filter { t in
                guard LocalCalendarDate.isTaskDueOn(recurrence: t.recurrence, ref: dayDate, calendar: cal) else { return false }
                return !t.shouldOmitFromDisplay(on: ymd, now: now, calendar: cal)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        let recInc = recSorted.filter { !$0.isCompleted(on: ymd) }
        let recDone = recSorted.filter { $0.isCompleted(on: ymd) }

        func appendOneTime(_ o: OneTimeReminder, rows: inout [CalendarTaskRow]) {
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

        func appendRecurring(_ t: RecurringTask, rows: inout [CalendarTaskRow]) {
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

        var rows: [CalendarTaskRow] = []
        for o in oneInc { appendOneTime(o, rows: &rows) }
        for t in recInc { appendRecurring(t, rows: &rows) }
        for o in oneDone { appendOneTime(o, rows: &rows) }
        for t in recDone { appendRecurring(t, rows: &rows) }
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
            Text("月历与当日列表中，已完成与未完成事项会一起显示（未完成在上）；勾选完成后仍会保留在列表中。点击日期打开详情。例行任务在「例行任务」页管理；时段提醒不出现在日历中。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .navigationTitle("日历")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $sheetDay) { item in
            CalendarDayTasksSheet(ymd: item.ymd, calendar: calendar, store: store)
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
        let tasks = TasksCalendarLogic.tasks(on: ymd, store: store, calendar: calendar)
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

    @State private var newOneTimeDraft: OneTimeReminder?
    @State private var rowPendingDelete: CalendarTaskRow?

    private var list: [CalendarTaskRow] {
        TasksCalendarLogic.tasks(on: ymd, store: store, calendar: calendar)
    }

    /// 展示区域右下悬浮添加（不占用标题栏、不做横向色条）。
    private var daySheetFloatingAddButton: some View {
        Button {
            openAddOneTime()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            Circle()
                .fill(Color.accentColor)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .accessibilityLabel("添加定时提醒")
        .help("添加定时提醒")
        .keyboardShortcut(.defaultAction)
    }

    private var closeToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #else
        return .cancellationAction
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if list.isEmpty {
                        ContentUnavailableView(
                            "当天暂无事项",
                            systemImage: "calendar",
                            description: Text("点击右下角「＋」添加定时提醒（或按 Return）；例行任务请在「例行任务」中创建。时段提醒仅出现在「时段提醒」页与小组件。")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(list) { row in
                                    dayDetailRow(row, ymd: ymd)
                                }
                            }
                            .padding(16)
                            .padding(.bottom, 44)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                daySheetFloatingAddButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
            }
            .navigationTitle(formattedDayHeader(ymd))
            .toolbar {
                ToolbarItem(placement: closeToolbarPlacement) {
                    Button("关闭") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .confirmationDialog(
                deleteConfirmTitle,
                isPresented: Binding(
                    get: { rowPendingDelete != nil },
                    set: { if !$0 { rowPendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let row = rowPendingDelete {
                        if row.isOneTime {
                            store.deleteOneTimeReminder(id: row.rawId)
                        } else {
                            store.deleteRecurringTask(id: row.rawId)
                        }
                    }
                    rowPendingDelete = nil
                }
                Button("取消", role: .cancel) { rowPendingDelete = nil }
            } message: {
                Text(deleteConfirmMessage)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .sheet(item: $newOneTimeDraft) { draft in
            OneTimeReminderEditSheet(store: store, reminder: draft, isNew: true, lockDateYmd: ymd)
        }
    }

    private func openAddOneTime() {
        newOneTimeDraft = OneTimeReminder.newDraftForCalendarDay(ymd: ymd, calendar: calendar)
    }

    private var deleteConfirmTitle: String {
        guard let row = rowPendingDelete else { return "删除" }
        return row.isOneTime ? "删除定时提醒" : "删除例行任务"
    }

    private var deleteConfirmMessage: String {
        guard let row = rowPendingDelete else { return "" }
        let name = row.title
        if row.isOneTime {
            return "确定删除「\(name)」？将一并取消尚未触发的通知。"
        }
        return "确定删除「\(name)」？此为例行任务：将从所有日期移除，并取消已排定的提醒。"
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
        let done = dayDetailRowLiveCompleted(row, ymd: ymd)
        let barFill = TasksCalendarLogic.taskBarFill(kind: row.kind, isCompleted: done)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(barFill)
                .frame(width: 4, height: 40)
                .opacity(done ? 0.85 : 1)
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
                            .foregroundStyle(done ? .tertiary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(done ? Color.secondary.opacity(0.07) : Color.secondary.opacity(0.14)))
                        Text(row.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(done ? .tertiary : .primary)
                            .strikethrough(done, color: .secondary)
                    }
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(done ? .tertiary : .secondary)
                        .strikethrough(done, color: Color.secondary.opacity(0.8))
                }
            }
            .toggleStyle(.checkbox)
            Button {
                rowPendingDelete = row
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(row.isOneTime ? "删除该定时提醒" : "删除该例行任务（所有日期）")
            .accessibilityLabel("删除")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(done ? Color(nsColor: .controlBackgroundColor).opacity(0.55) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(done ? Color.secondary.opacity(0.22) : Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        TasksCalendarView()
            .environment(EfficiencyStore())
    }
}
