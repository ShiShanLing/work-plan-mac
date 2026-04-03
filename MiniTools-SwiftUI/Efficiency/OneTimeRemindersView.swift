//
//  OneTimeRemindersView.swift
//  MiniTools-SwiftUI
//

import AppKit
import SwiftUI

/// 一次性提醒 Tab：今日与 upcoming 列表、历史、新建/编辑。
struct OneTimeRemindersView: View {
    @Environment(EfficiencyStore.self) private var store
    @ObservedObject private var notifier = NotificationScheduler.shared

    @State private var sheetReminder: OneTimeReminder?
    /// 主列表删除确认（勿与历史 sheet 共用：sheet 打开时下层 confirmationDialog 在 macOS 上会挡住不出现）。
    @State private var pendingDeleteMain: OneTimeReminder?
    /// 历史记录 sheet 内删除确认（须挂在 sheet 自己的视图树上）。
    @State private var pendingDeleteHistory: OneTimeReminder?
    @State private var alertMessage: String?
    @State private var showCompletedHistorySheet = false
    @State private var historySearchText = ""

    private var sorted: [OneTimeReminder] {
        store.oneTimeReminders.sorted {
            ($0.fireDate()?.timeIntervalSince1970 ?? 0) < ($1.fireDate()?.timeIntervalSince1970 ?? 0)
        }
    }

    /// 未完成：未到期的排在前面，已到期的仍待勾选处理。
    private var pendingReminders: [OneTimeReminder] {
        sorted.filter { !$0.isCompleted }.sorted { a, b in
            let af = a.isFireTimeInFuture()
            let bf = b.isFireTimeInFuture()
            if af != bf { return af && !bf }
            return (a.fireDate()?.timeIntervalSince1970 ?? 0) < (b.fireDate()?.timeIntervalSince1970 ?? 0)
        }
    }

    private var completedReminders: [OneTimeReminder] {
        sorted.filter(\.isCompleted).sorted {
            ($0.fireDate()?.timeIntervalSince1970 ?? 0) > ($1.fireDate()?.timeIntervalSince1970 ?? 0)
        }
    }

    /// 待处理：按到期日 `dateYmd` 升序分节。
    private var pendingGrouped: [(ymd: String, items: [OneTimeReminder])] {
        let dict = Dictionary(grouping: pendingReminders, by: \.dateYmd)
        return dict.keys.sorted().map { ymd in
            let items = (dict[ymd] ?? []).sorted {
                ($0.fireDate()?.timeIntervalSince1970 ?? 0) < ($1.fireDate()?.timeIntervalSince1970 ?? 0)
            }
            return (ymd, items)
        }
    }

    /// 历史弹窗：筛选后的已完成项（搜索标题、提醒摘要、提醒日、完成日）。
    private var filteredCompletedReminders: [OneTimeReminder] {
        let q = historySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = completedReminders
        guard !q.isEmpty else { return base }
        return base.filter { r in
            let title = r.title
            let summary = r.formatFireSummary()
            let completedAt = r.completedAtYmd ?? ""
            return title.localizedCaseInsensitiveContains(q)
                || summary.localizedCaseInsensitiveContains(q)
                || r.dateYmd.localizedCaseInsensitiveContains(q)
                || completedAt.localizedCaseInsensitiveContains(q)
        }
    }

    /// 按「完成日」分节（无记录时退化为提醒日 `dateYmd`），日期降序。
    private var filteredHistoryGrouped: [(ymd: String, items: [OneTimeReminder])] {
        let dict = Dictionary(grouping: filteredCompletedReminders) { $0.completedAtYmd ?? $0.dateYmd }
        return dict.keys.sorted(by: >).map { ymd in
            let items = (dict[ymd] ?? []).sorted {
                ($0.fireDate()?.timeIntervalSince1970 ?? 0) > ($1.fireDate()?.timeIntervalSince1970 ?? 0)
            }
            return (ymd, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设定日期与时间，到点由系统本地通知一次，不重复。可勾选「已完成」备忘；完成后会取消尚未触发的通知。已完成项保留在本机，可打开「历史记录」搜索回溯。应用无需常驻后台。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("待处理（按到期日）")
                        .font(.headline)
                    Spacer()
                    Button {
                        sheetReminder = OneTimeReminder.default()
                    } label: {
                        Label("新建", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if pendingReminders.isEmpty {
                    Text("暂无未完成项")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(pendingGrouped, id: \.ymd) { group in
                        EfficiencyDateSectionHeader.label(ymd: group.ymd, count: group.items.count)
                        ForEach(group.items) { item in
                            reminderRow(item, store: store)
                        }
                    }
                }

                HStack(alignment: .center) {
                    Text("已完成")
                        .font(.headline)
                    Spacer()
                    Button {
                        showCompletedHistorySheet = true
                    } label: {
                        if completedReminders.isEmpty {
                            Label("历史记录", systemImage: "clock.arrow.circlepath")
                        } else {
                            Label("历史记录（\(completedReminders.count)）", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)

                if completedReminders.isEmpty {
                    Text("暂无已完成记录。勾选待办左侧方框后，可在此打开历史列表检索。")
                        .foregroundStyle(.tertiary)
                } else {
                    Text("使用「历史记录」在弹窗中按完成日浏览、搜索标题或日期。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("定时提醒")
        .task {
            await notifier.refreshAuthorizationStatus()
        }
        .sheet(item: $sheetReminder) { reminder in
            OneTimeReminderEditSheet(
                store: store,
                reminder: reminder,
                isNew: !store.oneTimeReminders.contains(where: { $0.id == reminder.id })
            )
        }
        .sheet(isPresented: $showCompletedHistorySheet) {
            completedHistorySheet
        }
        .onChange(of: showCompletedHistorySheet) { _, isOpen in
            if !isOpen { historySearchText = "" }
        }
        .confirmationDialog(
            "删除提醒",
            isPresented: Binding(
                get: { pendingDeleteMain != nil },
                set: { if !$0 { pendingDeleteMain = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let r = pendingDeleteMain {
                    store.deleteOneTimeReminder(id: r.id)
                }
                pendingDeleteMain = nil
            }
            Button("取消", role: .cancel) { pendingDeleteMain = nil }
        } message: {
            if let r = pendingDeleteMain {
                Text("确定删除「\(r.title.isEmpty ? "（无标题）" : r.title)」？")
            }
        }
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var completedHistorySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("搜索标题、提醒时间或日期…", text: $historySearchText)
                    .textFieldStyle(.roundedBorder)
                Text("按「完成日」分组（新勾选会记录完成日本地日期）。旧数据仅按提醒日归类。列表中可取消完成、编辑或删除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if filteredCompletedReminders.isEmpty {
                    ContentUnavailableView(
                        historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "尚无已完成项" : "无匹配结果",
                        systemImage: "magnifyingglass",
                        description: Text(
                            historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "在主界面勾选待办为已完成后，会出现在这里。"
                                : "试试其它关键词，或清空搜索框。"
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredHistoryGrouped, id: \.ymd) { group in
                                EfficiencyDateSectionHeader.label(ymd: group.ymd, count: group.items.count)
                                ForEach(group.items) { item in
                                    reminderRow(item, store: store, showCompletedMeta: true, deleteConfirmInHistorySheet: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 480, minHeight: 520)
            .navigationTitle("历史记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showCompletedHistorySheet = false
                    }
                }
            }
            .confirmationDialog(
                "删除提醒",
                isPresented: Binding(
                    get: { pendingDeleteHistory != nil },
                    set: { if !$0 { pendingDeleteHistory = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let r = pendingDeleteHistory {
                        store.deleteOneTimeReminder(id: r.id)
                    }
                    pendingDeleteHistory = nil
                }
                Button("取消", role: .cancel) { pendingDeleteHistory = nil }
            } message: {
                if let r = pendingDeleteHistory {
                    Text("确定删除「\(r.title.isEmpty ? "（无标题）" : r.title)」？")
                }
            }
        }
    }

    @ViewBuilder
    private func reminderRow(
        _ r: OneTimeReminder,
        store: EfficiencyStore,
        showCompletedMeta: Bool = false,
        deleteConfirmInHistorySheet: Bool = false
    ) -> some View {
        let expired = !r.isFireTimeInFuture()
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: Binding(
                get: { store.oneTimeReminders.first(where: { $0.id == r.id })?.isCompleted ?? false },
                set: { v in
                    Task { @MainActor in
                        await store.setOneTimeReminderCompleted(id: r.id, completed: v)
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(r.title.isEmpty ? "（无标题）" : r.title)
                    .font(.headline)
                    .strikethrough(r.isCompleted, color: .secondary)
                Text(r.formatFireSummary())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if r.isCompleted, showCompletedMeta {
                    if let c = r.completedAtYmd {
                        Text("完成于 \(EfficiencyDateSectionHeader.title(forYmd: c))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("完成日未记录（旧数据）· 提醒日见上")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else if r.isCompleted {
                    Text("已完成")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if expired {
                    Text("已过期")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if r.notifyEnabled, !r.notificationIds.isEmpty {
                    Text("已预约本地通知")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if r.notifyEnabled, notifier.isAuthorizationDenied {
                    Text("通知权限被拒，无法预约")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !r.notifyEnabled {
                    Text("未开启通知（仅备忘）")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button {
                if let cur = store.oneTimeReminders.first(where: { $0.id == r.id }) {
                    sheetReminder = cur
                }
            } label: {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.borderless)
            .disabled(r.isCompleted)
            .opacity(r.isCompleted ? 0.35 : 1)
            .help(
                r.isCompleted
                    ? "已完成项不会发通知，无需编辑；若要改内容请先取消勾选「已完成」。"
                    : "编辑"
            )
            Button {
                if deleteConfirmInHistorySheet {
                    pendingDeleteHistory = r
                } else {
                    pendingDeleteMain = r
                }
            } label: {
                Image(systemName: "trash.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .opacity(expired && !r.isCompleted ? 0.85 : 1)
    }
}
