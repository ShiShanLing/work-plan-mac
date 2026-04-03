//
//  EfficiencyStore.swift
//  MiniTools-SwiftUI
//

import Foundation
import Observation
import OSLog

/// 效率模块单一数据源：一次性提醒、循环任务、时段任务、项目清单；负责 JSON 持久化与通知/小组件刷新。
@MainActor
@Observable
final class EfficiencyStore {
    var oneTimeReminders: [OneTimeReminder] = []
    var recurringTasks: [RecurringTask] = []
    var hourlyWindowTasks: [HourlyWindowTask] = []
    var projectChecklists: [ProjectChecklist] = []
    private(set) var hasCompletedInitialLoad = false

    /// 为 true 时：不向系统 `add` 新通知（含冷启动与回前台续排），直到用户再次编辑任务或选「清空并重新排程」。
    private static let silenceAutoNotificationRescheduleKey = "minitools_silence_auto_notification_reschedule"

    private func resumeAutoNotificationRescheduling() {
        UserDefaults.standard.removeObject(forKey: Self.silenceAutoNotificationRescheduleKey)
    }

    /// Canvas 预览时勿挂到通知中心，避免 `UNUserNotificationCenter` / delegate 导致预览进程卡住或长时间 “Building…”。
    private static var isSwiftUIPreviewProcess: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    init() {
        if !Self.isSwiftUIPreviewProcess {
            NotificationScheduler.shared.efficiencyStore = self
        }
    }

    func loadInitial() async {
        guard !hasCompletedInitialLoad else { return }
        NotificationScheduler.shared.efficiencyStore = self

        let silence = UserDefaults.standard.bool(forKey: Self.silenceAutoNotificationRescheduleKey)

        let oneLoad = LocalJSONStore.loadOneTimeRemindersDetailed()
        oneTimeReminders = oneLoad.items
        let recLoad = LocalJSONStore.loadRecurringTasksDetailed()
        recurringTasks = recLoad.items

        // 已移除「每日汇总提醒」；清掉旧版可能仍存在的系统通知请求。
        NotificationScheduler.shared.cancelPending(identifiers: ["recurring.digest"])

        if !silence {
            let syncedOnce = await NotificationScheduler.shared.syncAllOneTimeReminders(oneTimeReminders)
            oneTimeReminders = syncedOnce
            if oneLoad.shouldWriteBack {
                LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
            }

            recurringTasks = await Self.parallelSyncRecurringTasks(recurringTasks)
            if recLoad.shouldWriteBack {
                LocalJSONStore.saveRecurringTasks(recurringTasks)
            }
        }

        let hwLoad = LocalJSONStore.loadHourlyWindowTasksDetailed()
        hourlyWindowTasks = hwLoad.items
        applyPersistedHourlyWindowDismissalsFromNotification()

        if !silence {
            await NotificationScheduler.shared.cancelOrphanHourlyWindowPendingNotifications(
                knownTaskIds: Set(hourlyWindowTasks.map(\.id))
            )
            hourlyWindowTasks = await Self.parallelSyncHourlyWindowTasks(hourlyWindowTasks)
            if hwLoad.shouldWriteBack {
                LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
            }
        }

        let pcLoad = LocalJSONStore.loadProjectChecklistsDetailed()
        var pcItems = pcLoad.items
        let didNormalize = Self.normalizeLoadedProjectChecklists(&pcItems)
        projectChecklists = Self.sortedProjectChecklists(pcItems)
        if pcLoad.shouldWriteBack || didNormalize {
            LocalJSONStore.saveProjectChecklists(projectChecklists)
        }

        await NotificationScheduler.shared.refreshAuthorizationStatus()
        hasCompletedInitialLoad = true
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 移除系统在「待触发队列」和通知中心里与本应用相关的全部条目（**含所有未来已排程**），并清空各任务上缓存的 `notificationIds` 后写盘；**不会**再向系统添加新请求，直到你编辑某条任务或选「清空并重新排程」。
    func clearAllNotificationsOnlyPersistIds() {
        UserDefaults.standard.set(true, forKey: Self.silenceAutoNotificationRescheduleKey)
        NotificationScheduler.shared.removeEveryPendingAndDeliveredNotification()
        for i in oneTimeReminders.indices { oneTimeReminders[i].notificationIds = [] }
        for i in recurringTasks.indices { recurringTasks[i].notificationIds = [] }
        for i in hourlyWindowTasks.indices { hourlyWindowTasks[i].notificationIds = [] }
        LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
        LocalJSONStore.saveRecurringTasks(recurringTasks)
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        Task {
            await NotificationScheduler.shared.refreshAuthorizationStatus()
        }
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 清空系统通知队列里全部待定与已送达条目后，按当前 JSON 中的任务重新排队（消除测试/僵尸提醒）。
    func purgeAllNotificationQueueAndResync() async {
        resumeAutoNotificationRescheduling()
        NotificationScheduler.shared.removeEveryPendingAndDeliveredNotification()

        for i in oneTimeReminders.indices { oneTimeReminders[i].notificationIds = [] }
        for i in recurringTasks.indices { recurringTasks[i].notificationIds = [] }
        for i in hourlyWindowTasks.indices { hourlyWindowTasks[i].notificationIds = [] }

        oneTimeReminders = await NotificationScheduler.shared.syncAllOneTimeReminders(oneTimeReminders)
        LocalJSONStore.saveOneTimeReminders(oneTimeReminders)

        recurringTasks = await Self.parallelSyncRecurringTasks(recurringTasks)
        LocalJSONStore.saveRecurringTasks(recurringTasks)

        await NotificationScheduler.shared.cancelOrphanHourlyWindowPendingNotifications(
            knownTaskIds: Set(hourlyWindowTasks.map(\.id))
        )
        hourlyWindowTasks = await Self.parallelSyncHourlyWindowTasks(hourlyWindowTasks)
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)

        await NotificationScheduler.shared.refreshAuthorizationStatus()
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 应用回到前台时续排「每 N 小时」与例行任务系统通知（单次触发队列会耗尽）。
    func refreshRecurringAndHourlyNotifications() async {
        applyPersistedHourlyWindowDismissalsFromNotification()
        guard !UserDefaults.standard.bool(forKey: Self.silenceAutoNotificationRescheduleKey) else { return }
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

    /// 进行中 vs 已归档；组内先按 `sidebarOrder`，再按截止日、标题（兼容旧数据全 0）。
    private static func sortedProjectChecklists(_ items: [ProjectChecklist]) -> [ProjectChecklist] {
        items.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted && b.isCompleted }
            if a.sidebarOrder != b.sidebarOrder { return a.sidebarOrder < b.sidebarOrder }
            let ad = a.dueYmd ?? "9999-12-31"
            let bd = b.dueYmd ?? "9999-12-31"
            if ad != bd { return ad < bd }
            return a.title.localizedCompare(b.title) == .orderedAscending
        }
    }

    private static func legacyActiveCompare(_ a: ProjectChecklist, _ b: ProjectChecklist) -> Bool {
        let ad = a.dueYmd ?? "9999-12-31"
        let bd = b.dueYmd ?? "9999-12-31"
        if ad != bd { return ad < bd }
        return a.title.localizedCompare(b.title) == .orderedAscending
    }

    private static func legacyArchivedCompare(_ a: ProjectChecklist, _ b: ProjectChecklist) -> Bool {
        let ad = a.completedAtYmd ?? a.createdAt
        let bd = b.completedAtYmd ?? b.createdAt
        if ad != bd { return ad > bd }
        return a.title.localizedCompare(b.title) == .orderedAscending
    }

    /// 旧 JSON 无 `sidebarOrder` / `listOrder` 时补一次顺序，并返回是否改动了模型（需写盘）。
    @discardableResult
    private static func normalizeLoadedProjectChecklists(_ items: inout [ProjectChecklist]) -> Bool {
        var changed = false
        let active = items.enumerated().filter { !$0.element.isCompleted }
        if active.count > 1, active.allSatisfy({ $0.element.sidebarOrder == 0 }) {
            let order = active.sorted { legacyActiveCompare($0.element, $1.element) }.map(\.offset)
            for (rank, idx) in order.enumerated() {
                items[idx].sidebarOrder = rank
            }
            changed = true
        }
        let archived = items.enumerated().filter { $0.element.isCompleted }
        if archived.count > 1, archived.allSatisfy({ $0.element.sidebarOrder == 0 }) {
            let order = archived.sorted { legacyArchivedCompare($0.element, $1.element) }.map(\.offset)
            for (rank, idx) in order.enumerated() {
                items[idx].sidebarOrder = rank
            }
            changed = true
        }
        for i in items.indices {
            if migrateSubItemListOrdersIfNeeded(&items[i].items) {
                changed = true
            }
            for j in items[i].items.indices {
                let next = items[i].items[j].details.withIncompleteDetailsFirst()
                if next.map(\.id) != items[i].items[j].details.map(\.id) {
                    items[i].items[j].details = next
                    changed = true
                }
            }
        }
        return changed
    }

    /// 若全部子项 `listOrder == 0`，按文件中的顺序分配 0…n（未完成、已完成各一条链）。
    @discardableResult
    private static func migrateSubItemListOrdersIfNeeded(_ items: inout [ProjectChecklistSubItem]) -> Bool {
        guard !items.isEmpty, items.allSatisfy({ $0.listOrder == 0 }) else { return false }
        var o = 0
        var d = 0
        for j in items.indices {
            if items[j].isCompleted {
                items[j].listOrder = d
                d += 1
            } else {
                items[j].listOrder = o
                o += 1
            }
        }
        return true
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
        resumeAutoNotificationRescheduling()
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
        resumeAutoNotificationRescheduling()
        if let r = oneTimeReminders.first(where: { $0.id == id }) {
            NotificationScheduler.shared.cancelPending(identifiers: r.notificationIds)
        }
        oneTimeReminders.removeAll { $0.id == id }
        LocalJSONStore.saveOneTimeReminders(oneTimeReminders)
        MiniToolsWidgetReloader.reloadAll()
    }

    func setOneTimeReminderCompleted(id: String, completed: Bool) async {
        resumeAutoNotificationRescheduling()
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
        resumeAutoNotificationRescheduling()
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
        resumeAutoNotificationRescheduling()
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
        resumeAutoNotificationRescheduling()
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
        resumeAutoNotificationRescheduling()
        await NotificationScheduler.shared.cancelPendingHourlyWindowNotifications(taskId: id)
        if let t = hourlyWindowTasks.first(where: { $0.id == id }) {
            NotificationScheduler.shared.cancelPending(identifiers: t.notificationIds)
        }
        hourlyWindowTasks.removeAll { $0.id == id }
        LocalJSONStore.saveHourlyWindowTasks(hourlyWindowTasks)
        MiniToolsWidgetReloader.reloadAll()
    }

    func upsertProjectChecklist(_ checklist: ProjectChecklist) {
        var p = checklist
        p.normalizeDateOrder()
        var list = projectChecklists
        if let idx = list.firstIndex(where: { $0.id == p.id }) {
            list[idx] = p
        } else {
            let peers = list.filter { $0.isCompleted == p.isCompleted }
            p.sidebarOrder = (peers.map(\.sidebarOrder).max() ?? -1) + 1
            list.append(p)
        }
        projectChecklists = Self.sortedProjectChecklists(list)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    func deleteProjectChecklist(id: String) {
        projectChecklists.removeAll { $0.id == id }
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    func setProjectChecklistCompleted(id: String, completed: Bool) {
        guard let idx = projectChecklists.firstIndex(where: { $0.id == id }) else { return }
        projectChecklists[idx].isCompleted = completed
        projectChecklists[idx].completedAtYmd = completed ? LocalCalendarDate.localYmd(Date()) : nil
        let peers = projectChecklists.filter { $0.isCompleted == completed && $0.id != id }
        projectChecklists[idx].sidebarOrder = (peers.map(\.sidebarOrder).max() ?? -1) + 1
        projectChecklists = Self.sortedProjectChecklists(projectChecklists)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    func setProjectChecklistSubItemCompleted(projectId: String, subItemId: String, completed: Bool) {
        guard let pIdx = projectChecklists.firstIndex(where: { $0.id == projectId }) else { return }
        guard let sIdx = projectChecklists[pIdx].items.firstIndex(where: { $0.id == subItemId }) else { return }
        projectChecklists[pIdx].items[sIdx].isCompleted = completed
        projectChecklists[pIdx].items[sIdx].completedAtYmd = completed ? LocalCalendarDate.localYmd(Date()) : nil
        let subs = projectChecklists[pIdx].items
        if completed {
            let maxDone = subs.filter { $0.isCompleted && $0.id != subItemId }.map(\.listOrder).max() ?? -1
            projectChecklists[pIdx].items[sIdx].listOrder = maxDone + 1
        } else {
            let maxOpen = subs.filter { !$0.isCompleted && $0.id != subItemId }.map(\.listOrder).max() ?? -1
            projectChecklists[pIdx].items[sIdx].listOrder = maxOpen + 1
        }
        projectChecklists = Self.sortedProjectChecklists(projectChecklists)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 将子任务标为已完成，并把其下所有尚未完成的细节标为已完成（用于勾选子任务前的批量确认）。
    func completeProjectChecklistSubItemAndAllDetails(projectId: String, subItemId: String) {
        guard let pIdx = projectChecklists.firstIndex(where: { $0.id == projectId }) else { return }
        guard let sIdx = projectChecklists[pIdx].items.firstIndex(where: { $0.id == subItemId }) else { return }
        let ymd = LocalCalendarDate.localYmd(Date())
        for d in projectChecklists[pIdx].items[sIdx].details.indices where !projectChecklists[pIdx].items[sIdx].details[d].isCompleted {
            projectChecklists[pIdx].items[sIdx].details[d].isCompleted = true
            projectChecklists[pIdx].items[sIdx].details[d].completedAtYmd = ymd
        }
        projectChecklists[pIdx].items[sIdx].details = projectChecklists[pIdx].items[sIdx].details.withIncompleteDetailsFirst()
        setProjectChecklistSubItemCompleted(projectId: projectId, subItemId: subItemId, completed: true)
    }

    func setProjectChecklistSubItemPriority(projectId: String, subItemId: String, priority: ProjectChecklistSubItemPriority) {
        guard let pIdx = projectChecklists.firstIndex(where: { $0.id == projectId }) else { return }
        guard let sIdx = projectChecklists[pIdx].items.firstIndex(where: { $0.id == subItemId }) else { return }
        projectChecklists[pIdx].items[sIdx].priority = priority
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 未完成或已完成子任务区内：把 `draggedId` 挪到 `beforeItemId` 之前；`beforeItemId == nil` 表示末尾。
    func moveProjectChecklistSubItem(projectId: String, draggedItemId: String, incompleteSection: Bool, beforeItemId: String?) {
        guard let pIdx = projectChecklists.firstIndex(where: { $0.id == projectId }) else { return }
        var p = projectChecklists[pIdx]
        if incompleteSection {
            var open = p.items.filter { !$0.isCompleted }.sorted(by: ProjectChecklist.sortSubItemsOpen)
            var ids = open.map(\.id)
            guard let from = ids.firstIndex(of: draggedItemId) else { return }
            ids.remove(at: from)
            if let b = beforeItemId, let bi = ids.firstIndex(of: b) {
                ids.insert(draggedItemId, at: bi)
            } else {
                ids.append(draggedItemId)
            }
            open = ids.compactMap { id in open.first { $0.id == id } }
            for i in open.indices { open[i].listOrder = i }
            let done = p.items.filter(\.isCompleted).sorted(by: ProjectChecklist.sortSubItemsDone)
            p.items = open + done
        } else {
            var done = p.items.filter(\.isCompleted).sorted(by: ProjectChecklist.sortSubItemsDone)
            var ids = done.map(\.id)
            guard let from = ids.firstIndex(of: draggedItemId) else { return }
            ids.remove(at: from)
            if let b = beforeItemId, let bi = ids.firstIndex(of: b) {
                ids.insert(draggedItemId, at: bi)
            } else {
                ids.append(draggedItemId)
            }
            done = ids.compactMap { id in done.first { $0.id == id } }
            for i in done.indices { done[i].listOrder = i }
            let open = p.items.filter { !$0.isCompleted }.sorted(by: ProjectChecklist.sortSubItemsOpen)
            p.items = open + done
        }
        projectChecklists[pIdx] = p
        projectChecklists = Self.sortedProjectChecklists(projectChecklists)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 与 `List.onMove` 配合：整组 id 新顺序即 `sidebarOrder` 0…n。
    func applyChecklistSidebarOrder(completedGroup: Bool, orderedIds: [String]) {
        let peerIds = Set(projectChecklists.filter { $0.isCompleted == completedGroup }.map(\.id))
        guard peerIds == Set(orderedIds), peerIds.count == orderedIds.count else { return }
        for (rank, id) in orderedIds.enumerated() {
            guard let idx = projectChecklists.firstIndex(where: { $0.id == id }) else { return }
            projectChecklists[idx].sidebarOrder = rank
        }
        projectChecklists = Self.sortedProjectChecklists(projectChecklists)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 与 `List.onMove` 配合：未完成或已完成子任务区内的新顺序。
    func applySubItemOrder(projectId: String, incompleteSection: Bool, orderedIds: [String]) {
        guard let pIdx = projectChecklists.firstIndex(where: { $0.id == projectId }) else { return }
        var p = projectChecklists[pIdx]
        let peers = Set(
            p.items
                .filter { incompleteSection ? !$0.isCompleted : $0.isCompleted }
                .map(\.id)
        )
        guard peers == Set(orderedIds), peers.count == orderedIds.count else { return }
        if incompleteSection {
            var open: [ProjectChecklistSubItem] = []
            for (rank, id) in orderedIds.enumerated() {
                guard let idx = p.items.firstIndex(where: { $0.id == id && !$0.isCompleted }) else { return }
                var it = p.items[idx]
                it.listOrder = rank
                open.append(it)
            }
            let done = p.items.filter(\.isCompleted).sorted(by: ProjectChecklist.sortSubItemsDone)
            p.items = open + done
        } else {
            var done: [ProjectChecklistSubItem] = []
            for (rank, id) in orderedIds.enumerated() {
                guard let idx = p.items.firstIndex(where: { $0.id == id && $0.isCompleted }) else { return }
                var it = p.items[idx]
                it.listOrder = rank
                done.append(it)
            }
            let open = p.items.filter { !$0.isCompleted }.sorted(by: ProjectChecklist.sortSubItemsOpen)
            p.items = open + done
        }
        projectChecklists[pIdx] = p
        projectChecklists = Self.sortedProjectChecklists(projectChecklists)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 单个子任务内：按 `orderedDetailIds` 重写细节顺序（与 `List`/拖放 UI 配合）。
    func applySubItemDetailOrder(projectId: String, subItemId: String, orderedDetailIds: [String]) {
        guard let pIdx = projectChecklists.firstIndex(where: { $0.id == projectId }),
              let sIdx = projectChecklists[pIdx].items.firstIndex(where: { $0.id == subItemId }) else { return }
        var sub = projectChecklists[pIdx].items[sIdx]
        let peerIds = Set(sub.details.map(\.id))
        guard peerIds == Set(orderedDetailIds), peerIds.count == orderedDetailIds.count else { return }
        var newDetails: [ProjectChecklistSubItemDetail] = []
        for id in orderedDetailIds {
            guard let d = sub.details.first(where: { $0.id == id }) else { return }
            newDetails.append(d)
        }
        sub.details = newDetails.withIncompleteDetailsFirst()
        projectChecklists[pIdx].items[sIdx] = sub
        projectChecklists = Self.sortedProjectChecklists(projectChecklists)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 将一条细节从 `fromSubItemId` 挪到 `toSubItemId`，插在 `beforeDetailId` 所指行之前；`beforeDetailId == nil` 表示接到该子任务末尾。支持跨子任务。
    func moveProjectChecklistSubItemDetail(
        projectId: String,
        fromSubItemId: String,
        toSubItemId: String,
        detailId: String,
        beforeDetailId: String?
    ) {
        if beforeDetailId == detailId { return }
        guard let pIdx = projectChecklists.firstIndex(where: { $0.id == projectId }),
              let fromSIdx = projectChecklists[pIdx].items.firstIndex(where: { $0.id == fromSubItemId }),
              let fromDIdx = projectChecklists[pIdx].items[fromSIdx].details.firstIndex(where: { $0.id == detailId })
        else { return }

        var items = projectChecklists[pIdx].items
        var fromSub = items[fromSIdx]
        let piece = fromSub.details.remove(at: fromDIdx)
        items[fromSIdx] = fromSub

        guard let toSIdx = items.firstIndex(where: { $0.id == toSubItemId }) else {
            var revert = items[fromSIdx]
            revert.details.insert(piece, at: min(fromDIdx, revert.details.count))
            items[fromSIdx] = revert
            projectChecklists[pIdx].items = items
            projectChecklists = Self.sortedProjectChecklists(projectChecklists)
            LocalJSONStore.saveProjectChecklists(projectChecklists)
            MiniToolsWidgetReloader.reloadAll()
            return
        }

        var toSub = items[toSIdx]
        var dest = toSub.details
        let insertAt: Int
        if let before = beforeDetailId, let bi = dest.firstIndex(where: { $0.id == before }) {
            // 同子任务内从上往下拖：移除源后目标下移一位，`bi` 实际指向原来的位置，
            // 插在 `bi` 等于放回原位；需要 +1 才是「放到目标行之后」。
            if fromSubItemId == toSubItemId, fromDIdx <= bi {
                insertAt = bi + 1
            } else {
                insertAt = bi
            }
        } else {
            insertAt = dest.count
        }
        dest.insert(piece, at: min(insertAt, dest.count))
        toSub.details = dest.withIncompleteDetailsFirst()
        items[toSIdx] = toSub
        items[fromSIdx].details = items[fromSIdx].details.withIncompleteDetailsFirst()

        projectChecklists[pIdx].items = items
        projectChecklists = Self.sortedProjectChecklists(projectChecklists)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
        MiniToolsWidgetReloader.reloadAll()
    }

    /// 侧栏进行中或已归档组内拖拽排序（旧版 drop 逻辑，仍保留备查）。
    func moveProjectChecklistInSidebar(draggedId: String, completedGroup: Bool, beforeId: String?) {
        var list = projectChecklists
        let rowIds = list.filter { $0.isCompleted == completedGroup }
            .sorted { a, b in
                if a.sidebarOrder != b.sidebarOrder { return a.sidebarOrder < b.sidebarOrder }
                return completedGroup ? Self.legacyArchivedCompare(a, b) : Self.legacyActiveCompare(a, b)
            }
            .map(\.id)
        guard let from = rowIds.firstIndex(of: draggedId) else { return }
        var order = rowIds
        order.remove(at: from)
        if let b = beforeId, let bi = order.firstIndex(of: b) {
            order.insert(draggedId, at: bi)
        } else {
            order.append(draggedId)
        }
        for (rank, pid) in order.enumerated() {
            if let idx = list.firstIndex(where: { $0.id == pid }) {
                list[idx].sidebarOrder = rank
            }
        }
        projectChecklists = Self.sortedProjectChecklists(list)
        LocalJSONStore.saveProjectChecklists(projectChecklists)
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
        resumeAutoNotificationRescheduling()
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
        resumeAutoNotificationRescheduling()
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
