//
//  RecurringTasksView.swift
//  MiniTools-SwiftUI
//

import AppKit
import SwiftUI
private enum RecurrenceUIKind: String, CaseIterable, Identifiable {
    case daily
    case everyNDays
    case weekly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "每天"
        case .everyNDays: return "每 N 天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }
}

struct RecurringTasksView: View {
    @Environment(EfficiencyStore.self) private var store
    @ObservedObject private var notifier = NotificationScheduler.shared

    @State private var sheetTask: RecurringTask?
    @State private var pendingDelete: RecurringTask?
    @State private var digestAlert: String?

    private var todayYmd: String {
        LocalCalendarDate.localYmd(Date())
    }

    /// 从今天起连续若干天，按本地日分组列出待办（「每天」仅出现在今天，避免在多日重复铺满列表）。
    private let upcomingHorizonDays = 42

    private var recurringByDate: [(ymd: String, tasks: [RecurringTask])] {
        var cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var out: [(String, [RecurringTask])] = []
        for offset in 0 ..< upcomingHorizonDays {
            guard let dayDate = cal.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let ymd = LocalCalendarDate.localYmd(dayDate, calendar: cal)
            let tasks = tasksForGroupedDay(ymd: ymd, dayDate: dayDate, calendar: cal)
            if !tasks.isEmpty {
                out.append((ymd, tasks))
            }
        }
        return out
    }

    private func tasksForGroupedDay(ymd: String, dayDate: Date, calendar: Calendar) -> [RecurringTask] {
        store.recurringTasks.filter { task in
            guard task.isDueOn(dayDate, calendar: calendar) else { return false }
            switch task.recurrence {
            case .daily:
                guard ymd == todayYmd else { return false }
                return !task.isCompleted(on: ymd)
            default:
                return !task.isCompleted(on: ymd)
            }
        }.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private var sortedAll: [RecurringTask] {
        store.recurringTasks.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                digestCard

                HStack {
                    Text("近日待办（按日期）")
                        .font(.headline)
                    Spacer()
                }

                Text("「每天」重复的任务只在今天分组出现；每周、每月、每 N 天会在各自到期日下列出，表头旁的数字表示当天待办条数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if recurringByDate.isEmpty {
                    Text("当前日期范围内没有未勾选的例行待办")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(recurringByDate, id: \.ymd) { group in
                        EfficiencyDateSectionHeader.label(ymd: group.ymd, count: group.tasks.count)
                        ForEach(group.tasks) { task in
                            dueDayRow(task, ymd: group.ymd)
                        }
                    }
                }

                HStack {
                    Text("全部任务")
                        .font(.headline)
                    Spacer()
                    Button {
                        sheetTask = RecurringTask.default()
                    } label: {
                        Label("新建", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)

                if sortedAll.isEmpty {
                    Text("暂无任务，点击「新建」")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(sortedAll) { task in
                        taskRow(task)
                    }
                }

                Text("提醒由系统在设定时刻调度；应用未运行时同样可收到通知。可勾选完成记录仅保存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("例行任务")
        .task {
            await notifier.refreshAuthorizationStatus()
        }
        .sheet(item: $sheetTask) { task in
            RecurringTaskEditSheet(
                store: store,
                task: task,
                isNew: !store.recurringTasks.contains(where: { $0.id == task.id })
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
                    store.deleteRecurringTask(id: t.id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            if let t = pendingDelete {
                Text("确定删除「\(t.title.isEmpty ? "（无标题）" : t.title)」？")
            }
        }
        .alert("已保存", isPresented: Binding(
            get: { digestAlert != nil },
            set: { if !$0 { digestAlert = nil } }
        )) {
            Button("好", role: .cancel) { digestAlert = nil }
        } message: {
            Text(digestAlert ?? "")
        }
    }

    private var digestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("每日汇总提醒")
                .font(.headline)
            Text("每天在固定时间由系统提醒一次，可与各任务的到点提醒同时开启。数据仅保存在本机。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("开启", isOn: Binding(
                get: { store.digestPrefs.enabled },
                set: { v in
                    var p = store.digestPrefs
                    p.enabled = v
                    store.digestPrefs = p
                }
            ))

            HStack {
                Text("时间")
                Spacer()
                HourMinuteFields(hour: Binding(
                    get: { store.digestPrefs.hour },
                    set: { v in
                        var p = store.digestPrefs
                        p.hour = min(23, max(0, v))
                        store.digestPrefs = p
                    }
                ), minute: Binding(
                    get: { store.digestPrefs.minute },
                    set: { v in
                        var p = store.digestPrefs
                        p.minute = min(59, max(0, v))
                        store.digestPrefs = p
                    }
                ))
            }

            Button("保存提醒设置") {
                Task {
                    let prefs = store.digestPrefs
                    await store.saveDigest(prefs)
                    digestAlert = prefs.enabled ? "已更新每日汇总提醒" : "已关闭每日汇总提醒"
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func dueDayRow(_ task: RecurringTask, ymd: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.recurringTasks.first(where: { $0.id == task.id })?.isCompleted(on: ymd) ?? false },
                set: { store.setTaskCompleted(taskId: task.id, ymd: ymd, done: $0) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title.isEmpty ? "（无标题）" : task.title)
                    .font(.headline)
                    .strikethrough(store.recurringTasks.first(where: { $0.id == task.id })?.isCompleted(on: ymd) ?? false, color: .secondary)
                Text(LocalCalendarDate.recurrenceLabel(task.recurrence))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if task.notifyEnabled, notifier.isAuthorizationDenied {
                    Text("通知权限被拒")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button {
                guard let full = store.recurringTasks.first(where: { $0.id == task.id }) else { return }
                sheetTask = full
            } label: {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func taskRow(_ task: RecurringTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title.isEmpty ? "（无标题）" : task.title)
                    .font(.headline)
                Text(LocalCalendarDate.recurrenceLabel(task.recurrence))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !task.isDueOn() {
                    Text("今天不提醒")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button {
                sheetTask = task
            } label: {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.borderless)
            Button {
                pendingDelete = task
            } label: {
                Image(systemName: "trash.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Hour / minute fields

private struct HourMinuteFields: View {
    @Binding var hour: Int
    @Binding var minute: Int
    @State private var hourText: String = ""
    @State private var minuteText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            TextField("时", text: $hourText)
                .frame(width: 40)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onAppear { hourText = String(hour) }
                .onChange(of: hourText) { _, new in
                    guard let n = Int(new), new.count <= 2 else { return }
                    hour = min(23, max(0, n))
                }
                .onChange(of: hour) { _, new in
                    hourText = String(new)
                }
            Text(":")
            TextField("分", text: $minuteText)
                .frame(width: 40)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .onAppear { minuteText = String(minute) }
                .onChange(of: minuteText) { _, new in
                    guard let n = Int(new), new.count <= 2 else { return }
                    minute = min(59, max(0, n))
                }
                .onChange(of: minute) { _, new in
                    minuteText = String(new)
                }
        }
    }
}

// MARK: - Task sheet

private struct RecurringTaskEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let store: EfficiencyStore

    @State private var draft: RecurringTask
    @State private var kind: RecurrenceUIKind
    @State private var nDays: String
    @State private var anchorYmd: String
    @State private var weekdayJs: Int
    @State private var dayOfMonth: String

    private let isNew: Bool
    @State private var alertMessage: String?

    init(store: EfficiencyStore, task: RecurringTask, isNew: Bool) {
        self.store = store
        self.isNew = isNew
        _draft = State(initialValue: task)

        let today = LocalCalendarDate.localYmd(Date())
        switch task.recurrence {
        case .daily:
            _kind = State(initialValue: .daily)
            _nDays = State(initialValue: "2")
            _anchorYmd = State(initialValue: today)
            _weekdayJs = State(initialValue: 1)
            _dayOfMonth = State(initialValue: "1")
        case let .everyNDays(n, anchor):
            _kind = State(initialValue: .everyNDays)
            _nDays = State(initialValue: String(n))
            _anchorYmd = State(initialValue: anchor)
            _weekdayJs = State(initialValue: 1)
            _dayOfMonth = State(initialValue: "1")
        case let .weekly(w):
            _kind = State(initialValue: .weekly)
            _nDays = State(initialValue: "2")
            _anchorYmd = State(initialValue: today)
            _weekdayJs = State(initialValue: w)
            _dayOfMonth = State(initialValue: "1")
        case let .monthly(d):
            _kind = State(initialValue: .monthly)
            _nDays = State(initialValue: "2")
            _anchorYmd = State(initialValue: today)
            _weekdayJs = State(initialValue: 1)
            _dayOfMonth = State(initialValue: String(d))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.title.isEmpty && isNew ? "新建任务" : "编辑任务")
                .font(.title2.bold())
                .padding(.bottom, 12)

            Form {
                TextField("名称", text: $draft.title)
                    .textFieldStyle(.roundedBorder)

                Picker("重复", selection: $kind) {
                    ForEach(RecurrenceUIKind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }

                if kind == .everyNDays {
                    TextField("间隔天数（2 = 隔一天一次）", text: $nDays)
                        .textFieldStyle(.roundedBorder)
                    TextField("起始参考日（YYYY-MM-DD）", text: $anchorYmd)
                        .textFieldStyle(.roundedBorder)
                }

                if kind == .weekly {
                    let labels = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                        ForEach(0 ..< 7, id: \.self) { idx in
                            Button {
                                weekdayJs = idx
                            } label: {
                                Text(labels[idx])
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(weekdayJs == idx ? Color.accentColor : .secondary)
                        }
                    }
                }

                if kind == .monthly {
                    TextField("每月几号（缺日期的月份会按最后一天算）", text: $dayOfMonth)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("到点本地提醒", isOn: $draft.notifyEnabled)

                if draft.notifyEnabled {
                    HStack {
                        Text("提醒时刻")
                        Spacer()
                        HourMinuteFields(hour: $draft.notifyHour, minute: $draft.notifyMinute)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 420)
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func builtRecurrence() -> Recurrence? {
        switch kind {
        case .daily:
            return .daily
        case .everyNDays:
            guard let n = Int(nDays), n >= 1 else { return nil }
            let anchor = anchorYmd.trimmingCharacters(in: .whitespacesAndNewlines)
            guard anchor.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            return .everyNDays(intervalDays: n, anchorDate: anchor)
        case .weekly:
            return .weekly(weekdayJs: weekdayJs)
        case .monthly:
            guard let d = Int(dayOfMonth), (1 ... 31).contains(d) else { return nil }
            return .monthly(dayOfMonth: d)
        }
    }

    @MainActor
    private func save() async {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            alertMessage = "请填写任务名称"
            return
        }
        guard let r = builtRecurrence() else {
            alertMessage = "请检查重复规则（间隔天数、每月日期、起始日格式等）"
            return
        }
        draft.title = title
        draft.recurrence = r
        draft.notifyHour = min(23, max(0, draft.notifyHour))
        draft.notifyMinute = min(59, max(0, draft.notifyMinute))

        await store.upsertRecurringTask(draft)
        dismiss()
    }
}
