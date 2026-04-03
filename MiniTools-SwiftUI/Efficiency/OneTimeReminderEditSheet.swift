//
//  OneTimeReminderEditSheet.swift
//  MiniTools-SwiftUI
//

import SwiftUI

/// 日历弹层里的月份、星期等按简体中文显示（不依赖系统首选语言是否为英文）。
enum ReminderDatePickerChinese {
    static let locale = Locale(identifier: "zh-Hans")
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.timeZone = .current
        return c
    }
}

/// 一次性提醒的新建或编辑表单（日期时间、标题、完成态限制）。
struct OneTimeReminderEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 显式持有 `Observable` 模型，避免在 `.sheet` 的逃逸 `async` 闭包里捕获 `@Environment` 投影导致 `await` 之后野指针（与通知权限无关）。
    private let store: EfficiencyStore

    @State private var draft: OneTimeReminder
    @State private var fireAt: Date
    private let isNew: Bool
    /// 从日历进入时传入：锁定为当天 `YYYY-MM-DD`，仅允许改时分（秒始终为 0）。
    private let lockDateYmd: String?

    @State private var alertMessage: String?

    /// 已完成的一次性提醒不会预约通知；避免误编辑以为改完还会继续响。
    private var editingBlockedByCompleted: Bool {
        !isNew && draft.isCompleted
    }

    init(store: EfficiencyStore, reminder: OneTimeReminder, isNew: Bool, lockDateYmd: String? = nil) {
        self.store = store
        self.isNew = isNew
        self.lockDateYmd = lockDateYmd
        _draft = State(initialValue: reminder)
        let cal = Calendar.current
        let fd = reminder.fireDate() ?? reminder.defaultFireDateFallback(cal: cal)
        if let lock = lockDateYmd,
           let day = LocalCalendarDate.parseLocalYmd(lock, calendar: cal) {
            let h = cal.component(.hour, from: fd)
            let m = cal.component(.minute, from: fd)
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = h
            comps.minute = m
            comps.second = 0
            comps.nanosecond = 0
            _fireAt = State(initialValue: cal.date(from: comps) ?? fd)
        } else {
            _fireAt = State(initialValue: fd)
        }
    }

    private var fireAtSelection: Binding<Date> {
        Binding(
            get: { fireAt },
            set: { newValue in
                guard let ymd = lockDateYmd else {
                    fireAt = newValue
                    return
                }
                let cal = Calendar.current
                let h = cal.component(.hour, from: newValue)
                let m = cal.component(.minute, from: newValue)
                guard let day = LocalCalendarDate.parseLocalYmd(ymd, calendar: cal) else {
                    fireAt = newValue
                    return
                }
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = h
                comps.minute = m
                comps.second = 0
                comps.nanosecond = 0
                fireAt = cal.date(from: comps) ?? newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "新建提醒" : "编辑提醒")
                .font(.title2.bold())
                .padding(.bottom, 12)

            if editingBlockedByCompleted {
                Text("此项已勾选为「已完成」，不会发送通知。若需修改内容或时间，请先在列表中取消「已完成」后再打开编辑。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            Form {
                TextField("要做什么事", text: $draft.title)
                    .textFieldStyle(.roundedBorder)

                if let ymd = lockDateYmd {
                    Text("日期：\(lockedDayLabel(ymd))（由日历选定，不可更改）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    DatePicker("时间", selection: fireAtSelection, displayedComponents: [.hourAndMinute])
                } else {
                    DatePicker("日期与时间", selection: $fireAt, displayedComponents: [.date, .hourAndMinute])
                }

                Toggle("到点本地通知一次", isOn: $draft.notifyEnabled)

                Text("关闭通知后仅保存为本地备忘，仍会显示在列表中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .disabled(editingBlockedByCompleted)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editingBlockedByCompleted)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 360)
        .environment(\.locale, ReminderDatePickerChinese.locale)
        .environment(\.calendar, ReminderDatePickerChinese.calendar)
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
        if editingBlockedByCompleted {
            alertMessage = "已完成的任务不会发通知。请先在列表取消「已完成」后再编辑。"
            return
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            alertMessage = "请填写提醒内容"
            return
        }

        let cal = Calendar.current
        let rounded = OneTimeReminder.roundToMinute(fireAt, calendar: cal)
        if let ymd = lockDateYmd {
            draft.dateYmd = ymd
            draft.hour = cal.component(.hour, from: rounded)
            draft.minute = cal.component(.minute, from: rounded)
        } else {
            draft.dateYmd = LocalCalendarDate.localYmd(rounded, calendar: cal)
            draft.hour = cal.component(.hour, from: rounded)
            draft.minute = cal.component(.minute, from: rounded)
        }

        guard draft.fireDate() != nil else {
            alertMessage = "日期或时间无效，请检查"
            return
        }

        if draft.notifyEnabled, !draft.isFireTimeInFuture() {
            alertMessage = "所选时间已过，无法预约通知。可关掉「到点本地通知一次」仅保存备忘，或改选未来时间。"
            return
        }

        await store.upsertOneTimeReminder(draft)
        dismiss()
    }

    private func lockedDayLabel(_ ymd: String) -> String {
        guard let d = LocalCalendarDate.parseLocalYmd(ymd, calendar: Calendar.current) else { return ymd }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh-Hans")
        df.dateStyle = .long
        df.timeStyle = .none
        return df.string(from: d)
    }
}

extension OneTimeReminder {
    fileprivate func defaultFireDateFallback(cal: Calendar) -> Date {
        OneTimeReminder.roundToMinute(Date(), calendar: cal)
    }
}
