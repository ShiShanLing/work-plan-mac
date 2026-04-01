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
    var digestPrefs: DigestPrefs = .default
    private(set) var hasCompletedInitialLoad = false

    func loadInitial() async {
        guard !hasCompletedInitialLoad else { return }
        let oneLoad = LocalJSONStore.loadOneTimeRemindersDetailed()
        oneTimeReminders = oneLoad.items
        let recLoad = LocalJSONStore.loadRecurringTasksDetailed()
        recurringTasks = recLoad.items
        let digestLoad = LocalJSONStore.loadDigestPrefsDetailed()
        digestPrefs = digestLoad.prefs

        let syncedOnce = await NotificationScheduler.shared.syncAllOneTimeReminders(oneTimeReminders)
        oneTimeReminders = syncedOnce
        if oneLoad.shouldWriteBack {
            LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
        }

        var nextTasks: [RecurringTask] = []
        for var t in recurringTasks {
            t = await NotificationScheduler.shared.syncRecurringTask(t)
            nextTasks.append(t)
        }
        recurringTasks = nextTasks
        if recLoad.shouldWriteBack {
            LocalJSONStore.saveRecurringTasks(recurringTasks)
        }

        if digestLoad.shouldWriteBack {
            await NotificationScheduler.shared.syncDigest(digestPrefs)
        }
        await NotificationScheduler.shared.refreshAuthorizationStatus()
        hasCompletedInitialLoad = true
        MiniToolsWidgetReloader.reloadAll()
    }

    func saveDigest(_ prefs: DigestPrefs) async {
        digestPrefs = prefs
        LocalJSONStore.saveDigestPrefs(prefs)
        await NotificationScheduler.shared.syncDigest(prefs)
        await NotificationScheduler.shared.refreshAuthorizationStatus()
        MiniToolsWidgetReloader.reloadAll()
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
}
