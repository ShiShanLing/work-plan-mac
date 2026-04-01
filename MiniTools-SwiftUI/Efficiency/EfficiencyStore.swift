//
//  EfficiencyStore.swift
//  MiniTools-SwiftUI
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class EfficiencyStore {
    var oneTimeReminders: [OneTimeReminder] = []
    var recurringTasks: [RecurringTask] = []
    var hourlyWindowTasks: [HourlyWindowTask] = []
    private(set) var hasCompletedInitialLoad = false

    init() {
        NotificationScheduler.shared.efficiencyStore = self
    }

    func loadInitial() async {
        guard !hasCompletedInitialLoad else { return }
        NotificationScheduler.shared.efficiencyStore = self

        let oneLoad = LocalJSONStore.loadOneTimeRemindersDetailed()
        oneTimeReminders = oneLoad.items
        let recLoad = LocalJSONStore.loadRecurringTasksDetailed()
        recurringTasks = recLoad.items

        // 已移除「每日汇总提醒」；清掉旧版可能仍存在的系统通知请求。
        NotificationScheduler.shared.cancelPending(identifiers: ["recurring.digest"])

        let syncedOnce = await NotificationScheduler.shared.syncAllOneTimeReminders(oneTimeReminders)
        oneTimeReminders = syncedOnce
        if oneLoad.shouldWriteBack {
            LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
        }

        recurringTasks = await Self.parallelSyncRecurringTasks(recurringTasks)
        if recLoad.shouldWriteBack {
            LocalJSONStore.saveRecurringTasks(recurringTasks)
        }

        let hwLoad = LocalJSONStore.loadHourlyWindowTasksDetailed()
        hourlyWindowTasks = hwLoad.items
        applyPersistedHourlyWindowDismissalsFromNotification()

        await NotificationScheduler.shared.cancelOrphanHourlyWindowPendingNotifications(
            knownTaskIds: Set(hourlyWindowTasks.map(\.id))
        )
        hourlyWindowTasks = await Self.parallelSyncHourlyWindowTasks(hourlyWindowTasks)
        if hwLoad.shouldWriteBack {
            LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        }

        await NotificationScheduler.shared.refreshAuthorizationStatus()
        hasCompletedInitialLoad = true
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 应用回到前台时续排「每 N 小时」与例行任务系统通知（单次触发队列会耗尽）。
    func refreshRecurringAndHourlyNotifications() async {
        applyPersistedHourlyWindowDismissalsFromNotification()
        await NotificationScheduler.shared.cancelOrphanHourlyWindowPendingNotifications(
            knownTaskIds: Set(hourlyWindowTasks.map(\.id))
        )
        let recBefore = recurringTasks
        recurringTasks = await Self.parallelSyncRecurringTasks(recurringTasks)

        let hwBefore = hourlyWindowTasks
        hourlyWindowTasks = await Self.parallelSyncHourlyWindowTasks(hourlyWindowTasks)

        if recurringTasks != recBefore {
            LocalJSONStore.saveRecurringTasks(recurringTasks)
        }
        if hourlyWindowTasks != hwBefore {
            LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        }
    }

    private static func parallelSyncRecurringTasks(_ tasks: [RecurringTask]) async -> [RecurringTask] {
        guard !tasks.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, RecurringTask).self, returning: [RecurringTask].self) { group in
            for (i, t) in tasks.enumerated() {
                let item = t
                group.addTask {
                    (i, await NotificationScheduler.shared.syncRecurringTask(item))
                }
            }
            var buf: [(Int, RecurringTask)] = []
            buf.reserveCapacity(tasks.count)
            for await pair in group {
                buf.append(pair)
            }
            return buf.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func parallelSyncHourlyWindowTasks(_ tasks: [HourlyWindowTask]) async -> [HourlyWindowTask] {
        guard !tasks.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, HourlyWindowTask).self, returning: [HourlyWindowTask].self) { group in
            for (i, t) in tasks.enumerated() {
                let item = t
                group.addTask {
                    (i, await NotificationScheduler.shared.syncHourlyWindowTask(item))
                }
            }
            var buf: [(Int, HourlyWindowTask)] = []
            buf.reserveCapacity(tasks.count)
            for await pair in group {
                buf.append(pair)
            }
            return buf.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func upsertOneTimeReminder(_ reminder: OneTimeReminder) async {
        #if DEBUG
        AppLog.store.debug("upsertOneTime id=\(reminder.id, privacy: .public)")
        #endif
        var list = oneTimeReminders
        let synced = await NotificationScheduler.shared.syncOneTimeReminder(reminder)
        if let idx = list.firstIndex(where: { $0.id == synced.id }) {
            list[idx] = synced
        } else {
            list.append(synced)
        }
        oneTimeReminders = list.sorted {
            ($0.fireDate()?.timeIntervalSince1970 ?? 0) < ($1.fireDate()?.timeIntervalSince1970 ?? 0)
        }
        LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
        await NotificationScheduler.shared.refreshAuthorizationStatus()
        MiniToolsWidgetReloader.reloadAll()
    }

    func deleteOneTimeReminder(id: String) {
        if let r = oneTimeReminders.first(where: { $0.id == id }) {
            NotificationScheduler.shared.cancelPending(identifiers: r.notificationIds)
        }
        oneTimeReminders.removeAll { $0.id == id }
        LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
        MiniToolsWidgetReloader.reloadAll()
    }

    func setOneTimeReminderCompleted(id: String, completed: Bool) async {
        guard let idx = oneTimeReminders.firstIndex(where: { $0.id == id }) else { return }
        oneTimeReminders[idx].isCompleted = completed
        if completed {
            oneTimeReminders[idx].completedAtYmd = LocalCalendarDate.localYmd(Date())
        } else {
            oneTimeReminders[idx].completedAtYmd = nil
        }
        let synced = await NotificationScheduler.shared.syncOneTimeReminder(oneTimeReminders[idx])
        oneTimeReminders[idx] = synced
        LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
        MiniToolsWidgetReloader.reloadAll()
    }

    func upsertRecurringTask(_ task: RecurringTask) async {
        var list = recurringTasks
        let synced = await NotificationScheduler.shared.syncRecurringTask(task)
        if let idx = list.firstIndex(where: { $0.id == synced.id }) {
            list[idx] = synced
        } else {
            list.append(synced)
        }
        recurringTasks = list.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        LocalJSONStore.saveRecurringTasks(recurringTasks)
        await NotificationScheduler.shared.refreshAuthorizationStatus()
        MiniToolsWidgetReloader.reloadAll()
    }

    func deleteRecurringTask(id: String) {
        if let t = recurringTasks.first(where: { $0.id == id }) {
            NotificationScheduler.shared.cancelPending(identifiers: t.notificationIds)
        }
        recurringTasks.removeAll { $0.id == id }
        LocalJSONStore.saveRecurringTasks(recurringTasks)
        MiniToolsWidgetReloader.reloadAll()
    }

    func setTaskCompleted(taskId: String, ymd: String, done: Bool) {
        guard let idx = recurringTasks.firstIndex(where: { $0.id == taskId }) else { return }
        recurringTasks[idx].setCompleted(done, on: ymd)
        LocalJSONStore.saveRecurringTasks(recurringTasks)
        MiniToolsWidgetReloader.reloadAll()
    }

    func upsertHourlyWindowTask(_ task: HourlyWindowTask) async {
        var list = hourlyWindowTasks
        let synced = await NotificationScheduler.shared.syncHourlyWindowTask(task)
        if let idx = list.firstIndex(where: { $0.id == synced.id }) {
            list[idx] = synced
        } else {
            list.append(synced)
        }
        hourlyWindowTasks = list.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        await NotificationScheduler.shared.refreshAuthorizationStatus()
        MiniToolsWidgetReloader.reloadAll()
    }

    func deleteHourlyWindowTask(id: String) async {
        await NotificationScheduler.shared.cancelPendingHourlyWindowNotifications(taskId: id)
        if let t = hourlyWindowTasks.first(where: { $0.id == id }) {
            NotificationScheduler.shared.cancelPending(identifiers: t.notificationIds)
        }
        hourlyWindowTasks.removeAll { $0.id == id }
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        MiniToolsWidgetReloader.reloadAll()
    }

    func setHourlyWindowTaskCompleted(taskId: String, ymd: String, done: Bool) {
        guard let idx = hourlyWindowTasks.firstIndex(where: { $0.id == taskId }) else { return }
        hourlyWindowTasks[idx].setCompleted(done, on: ymd)
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 取消「今日不再提示」后重新按时间窗向系统排队（用户误点通知或需继续提醒时）。
    func restoreHourlyWindowTodaySchedule(taskId: String) async {
        let ymd = LocalCalendarDate.localYmd(Date())
        guard let idx = hourlyWindowTasks.firstIndex(where: { $0.id == taskId }) else { return }
        hourlyWindowTasks[idx].setCompleted(false, on: ymd)
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        let synced = await NotificationScheduler.shared.syncHourlyWindowTask(hourlyWindowTasks[idx])
        hourlyWindowTasks[idx] = synced
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 通知上点「不再提示」：今日标为已完成、取消该任务当前待定通知并按规则续排（不再含今日未完成档位）。
    func markHourlyWindowDoneFromNotification(taskId: String) async {
        guard let idx = hourlyWindowTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let ymd = LocalCalendarDate.localYmd(Date())
        hourlyWindowTasks[idx].setCompleted(true, on: ymd)
        NotificationScheduler.shared.cancelPending(identifiers: hourlyWindowTasks[idx].notificationIds)
        hourlyWindowTasks[idx].notificationIds = []
        let synced = await NotificationScheduler.shared.syncHourlyWindowTask(hourlyWindowTasks[idx])
        hourlyWindowTasks[idx] = synced
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        MiniToolsWidgetReloader.reloadAll()
        PendingHourlyWindowDismissStorage.remove(taskId: taskId)
    }

    /// 通知动作早于界面/store 就绪时写入的「今日完成」占位，启动后与 JSON 合并。
    private func applyPersistedHourlyWindowDismissalsFromNotification() {
        let pending = PendingHourlyWindowDismissStorage.takeAllForStartupMerge()
        guard !pending.isEmpty else { return }
        var changed = false
        for (taskId, ymd) in pending {
            if let idx = hourlyWindowTasks.firstIndex(where: { $0.id == taskId }) {
                hourlyWindowTasks[idx].setCompleted(true, on: ymd)
                changed = true
            }
        }
        if changed {
            LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
            MiniToolsWidgetReloader.reloadAll()
        }
    }
}
