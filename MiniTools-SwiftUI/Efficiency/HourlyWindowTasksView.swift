//
//  HourlyWindowTasksView.swift
//  MiniTools-SwiftUI
//

import AppKit
import SwiftUI

struct HourlyWindowTasksView: View {
    @Environment(EfficiencyStore.self) private var store
    @ObservedObject private var notifier = NotificationScheduler.shared

    @State private var sheetTask: HourlyWindowTask?
    @State private var pendingDelete: HourlyWindowTask?

    private var sortedAll: [HourlyWindowTask] {
        store.hourlyWindowTasks.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "用下方「开始 / 结束」各选日期与时间；保存时开始须不早于当前时刻，结束须整体晚于开始。结束选「次日」即跨夜。系统通知可点「不再提示」将今日该时段标为已完成并取消今日余下提醒。本地通知需定期打开应用续排。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("时段任务")
                        .font(.headline)
                    Spacer()
                    Button {
                        sheetTask = HourlyWindowTask.default()
                    } label: {
                        Label("新建", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if sortedAll.isEmpty {
                    Text("暂无任务，点击「新建」")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(sortedAll) { task in
                        taskRow(task)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("时段提醒")
        .task {
            await notifier.refreshAuthorizationStatus()
        }
        .sheet(item: $sheetTask) { task in
            HourlyWindowTaskEditSheet(
                store: store,
                task: task,
                isNew: !store.hourlyWindowTasks.contains(where: { $0.id == task.id })
            )
        }
        .confirmationDialog(
            "删除任务",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let t = pendingDelete {
                    Task { await store.deleteHourlyWindowTask(id: t.id) }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            if let t = pendingDelete {
                Text("确定删除「\(t.title.isEmpty ? "（无标题）" : t.title)」？")
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: HourlyWindowTask) -> some View {
        let live = store.hourlyWindowTasks.first(where: { $0.id == task.id }) ?? task
        let todayYmd = LocalCalendarDate.localYmd(Date())
        let todayNoMoreAlerts = live.isCompleted(on: todayYmd)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(live.title.isEmpty ? "（无标题）" : live.title)
                    .font(.headline)
                    .foregroundStyle(todayNoMoreAlerts ? .secondary : .primary)
                Text(live.summaryScheduleLabel())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if todayNoMoreAlerts {
                    Text("今日：不再提示 / 已完成（与通知上「不再提示」相同，今天不会再响）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("恢复今日提醒") {
                        Task { await store.restoreHourlyWindowTodaySchedule(taskId: live.id) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .controlSize(.small)
                } else if !live.notifyEnabled {
                    Text("未开启系统提醒（仅备忘）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if live.notifyEnabled, notifier.isAuthorizationDenied {
                    Text("通知权限被拒")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Button {
                sheetTask = live
            } label: {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.borderless)
            .disabled(todayNoMoreAlerts)
            .opacity(todayNoMoreAlerts ? 0.35 : 1)
            .help(
                todayNoMoreAlerts
                    ? "今日已点「不再提示」或标为完成，不能再编辑；请先点「恢复今日提醒」或等到次日。"
                    : "编辑"
            )
            Button {
                pendingDelete = live
            } label: {
                Image(systemName: "trash.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(todayNoMoreAlerts ? Color(nsColor: .controlBackgroundColor).opacity(0.72) : Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - 编辑

private struct HourlyWindowTaskEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let store: EfficiencyStore
    @State private var draft: HourlyWindowTask
    @State private var intervalText: String
    @State private var windowStartPicker: Date
    @State private var windowEndPicker: Date
    @State private var alertMessage: String?

    private let isNew: Bool

    /// 今日已在通知中点「不再提示」或同等完成态：与定时提醒「已完成」一样，保存也不会让今天再响。
    private var editingBlockedForToday: Bool {
        !isNew && draft.isCompleted(on: LocalCalendarDate.localYmd(Date()))
    }

    private var datePickerHint: String {
        let cal = Calendar.current
        let ds = cal.startOfDay(for: windowStartPicker)
        let de = cal.startOfDay(for: windowEndPicker)
        let delta = cal.dateComponents([.day], from: ds, to: de).day ?? 0
        if delta < 0 || delta > 1 {
            return "结束日期须为开始「当天」或「次日」，请修改。"
        }
        if delta == 0 {
            return "同一天内：结束须整体晚于开始。保存时开始不能早于当前时刻（精确到分钟）。"
        }
        return "跨夜：开始在第一天，结束在第二天；保存时开始须不早于当前时刻。"
    }

    private static func makePickers(from task: HourlyWindowTask) -> (Date, Date) {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let start = cal.date(bySettingHour: task.windowStartHour, minute: task.windowStartMinute, second: 0, of: base) ?? base
        let endDay = cal.date(byAdding: .day, value: task.windowEndDayOffset, to: base) ?? base
        let end = cal.date(bySettingHour: task.windowEndHour, minute: task.windowEndMinute, second: 0, of: endDay) ?? endDay
        return (start, end)
    }

    init(store: EfficiencyStore, task: HourlyWindowTask, isNew: Bool) {
        self.store = store
        self.isNew = isNew
        _draft = State(initialValue: task)
        _intervalText = State(initialValue: String(task.intervalMinutes))
        let pair = Self.makePickers(from: task)
        _windowStartPicker = State(initialValue: pair.0)
        _windowEndPicker = State(initialValue: pair.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.title.isEmpty && isNew ? "新建时段任务" : "编辑时段任务")
                .font(.title2.bold())
                .padding(.bottom, 12)

            if editingBlockedForToday {
                Text("今日已将此时段标为「已完成 / 不再提示」，系统今天不会再响。请先关闭本页，在列表点「恢复今日提醒」后再编辑；或次日再编辑。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            Form {
                TextField("名称", text: $draft.title)
                    .textFieldStyle(.roundedBorder)

                TextField("间隔（分钟，整数 1–1440）", text: $intervalText)
                    .textFieldStyle(.roundedBorder)

                DatePicker(
                    "开始（日期与时间）",
                    selection: $windowStartPicker,
                    displayedComponents: [.date, .hourAndMinute]
                )

                DatePicker(
                    "结束（日期与时间，跨夜则选次日）",
                    selection: $windowEndPicker,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Text(datePickerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("仅工作日", isOn: $draft.weekdaysOnly)

                Toggle("到点本地提醒（每一档触发时刻各一次）", isOn: $draft.notifyEnabled)
            }
            .formStyle(.grouped)
            .disabled(editingBlockedForToday)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editingBlockedForToday)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 460)
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @MainActor
    private func save() async {
        if editingBlockedForToday {
            alertMessage = "今日已「不再提示 / 完成」。请先在列表点「恢复今日提醒」。"
            return
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            alertMessage = "请填写任务名称"
            return
        }
        guard let n = Int(intervalText.trimmingCharacters(in: .whitespacesAndNewlines)), (1 ... 1440).contains(n) else {
            alertMessage = "间隔分钟请输入 1–1440 的整数"
            return
        }
        draft.intervalMinutes = n
        draft.title = title

        let cal = Calendar.current
        let d0 = cal.startOfDay(for: windowStartPicker)
        let d1 = cal.startOfDay(for: windowEndPicker)
        let dayDelta = cal.dateComponents([.day], from: d0, to: d1).day ?? 0
        guard (0 ... 1).contains(dayDelta) else {
            alertMessage = "结束日期只能是开始当天或次日"
            return
        }
        var nowComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        nowComps.second = 0
        nowComps.nanosecond = 0
        guard let nowFloor = cal.date(from: nowComps) else {
            alertMessage = "无法解析当前时间"
            return
        }
        guard windowStartPicker >= nowFloor else {
            alertMessage = "开始时间不能早于当前时间"
            return
        }
        guard windowEndPicker > windowStartPicker else {
            alertMessage = "结束须整体晚于开始（日期与时间）"
            return
        }
        draft.windowStartHour = cal.component(.hour, from: windowStartPicker)
        draft.windowStartMinute = cal.component(.minute, from: windowStartPicker)
        draft.windowEndHour = cal.component(.hour, from: windowEndPicker)
        draft.windowEndMinute = cal.component(.minute, from: windowEndPicker)
        draft.windowEndDayOffset = dayDelta

        if !draft.isValidWindow() {
            alertMessage = "时间窗无效，请检查时刻与日期"
            return
        }

        await store.upsertHourlyWindowTask(draft)
        dismiss()
    }
}
