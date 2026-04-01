//
//  NotificationScheduler.swift
//  MiniTools-SwiftUI
//
//  Uses UNUserNotificationCenter only: no app background timers; the OS delivers at fire time.
//

import Combine
import Foundation
import OSLog
import UserNotifications

private enum MiniToolsNotificationCategory {
    /// 定时提醒、例行任务（按天粒度）：仅「延迟 1 小时」。
    static let snoozeable = "minitools.snoozeable"
    /// 时段提醒（按分钟间隔）：仅「不再提示」= 今日该时段已完成并取消余下提醒。
    static let hourlyWindow = "minitools.hourlywindow"
}

private enum MiniToolsNotificationActionID {
    static let snooze1h = "minitools.snooze.1h"
    static let hourlyDoneToday = "minitools.hourly.doneToday"
}

/// `UNUserNotificationCenterDelegate` 必须由 `NSObject` 实现；若与 `@MainActor` 叠在同一类上，系统可能在任意线程回调 ObjC 路径，易触发异常访问。
/// 将 delegate 单独放在此类中，调度逻辑保留在 `@MainActor` 的 `NotificationScheduler`。
private final class NotificationCenterDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await NotificationScheduler.shared.handleNotificationActionResponse(response)
            completionHandler()
        }
    }
}

@MainActor
final class NotificationScheduler: ObservableObject {
    static let shared = NotificationScheduler()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// 供仅 `import SwiftUI` 的界面使用，避免在视图层引用 `UNAuthorizationStatus`（Swift 6 成员可见性）。
    var isAuthorizationDenied: Bool {
        authorizationStatus == .denied
    }

    /// 处理通知动作时需回写数据（如「今日时段已完成」）；由主界面 `onAppear` 注入。
    weak var efficiencyStore: EfficiencyStore?

    private let center = UNUserNotificationCenter.current()
    private let centerDelegate = NotificationCenterDelegateProxy()

    private func logNotificationAddFailure(_ error: Error, _ context: String) {
        AppLog.notifications.error("UNUserNotificationCenter.add failed [\(context, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
    }

    private init() {
        center.delegate = centerDelegate
        Self.registerNotificationCategories()
    }

    private static func registerNotificationCategories() {
        let snooze = UNNotificationAction(
            identifier: MiniToolsNotificationActionID.snooze1h,
            title: "延迟 1 小时",
            options: []
        )
        let doneToday = UNNotificationAction(
            identifier: MiniToolsNotificationActionID.hourlyDoneToday,
            title: "不再提示",
            options: [.destructive]
        )

        let daySnooze = UNNotificationCategory(
            identifier: MiniToolsNotificationCategory.snoozeable,
            actions: [snooze],
            intentIdentifiers: [],
            options: []
        )
        let hourlyOnly = UNNotificationCategory(
            identifier: MiniToolsNotificationCategory.hourlyWindow,
            actions: [doneToday],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([daySnooze, hourlyOnly])
    }

    /// 定时 / 例行：选「延迟 1 小时」时再排一条单次通知（仍为 `snoozeable`）。
    /// 时段：选「不再提示」则今日标完成并取消该任务余下待定通知。
    func handleNotificationActionResponse(_ response: UNNotificationResponse) async {
        let aid = response.actionIdentifier
        let original = response.notification.request.content
        let kind = original.userInfo["kind"] as? String

        if aid == MiniToolsNotificationActionID.hourlyDoneToday {
            guard kind == "hourly-window-task",
                  let taskId = original.userInfo["taskId"] as? String
            else { return }
            await efficiencyStore?.markHourlyWindowDoneFromNotification(taskId: taskId)
            return
        }

        guard aid == MiniToolsNotificationActionID.snooze1h else { return }
        // 时段通知不使用「延迟 1 小时」；旧版若仍含该动作则忽略。
        guard kind != "hourly-window-task" else { return }

        let next = UNMutableNotificationContent()
        next.title = original.title
        next.body = original.body
        next.sound = original.sound
        next.threadIdentifier = original.threadIdentifier
        next.categoryIdentifier = MiniToolsNotificationCategory.snoozeable
        next.userInfo = original.userInfo

        let cal = Calendar.current
        guard let when = cal.date(byAdding: .hour, value: 1, to: Date()) else { return }
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "minitools.snooze.\(Int(Date().timeIntervalSince1970 * 1000))"
        let req = UNNotificationRequest(identifier: id, content: next, trigger: trigger)
        do {
            try await center.add(req)
        } catch {
            logNotificationAddFailure(error, "snooze1h")
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Request alert permission when the user opts into notifications.
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationStatus = settings.authorizationStatus
            return true
        case .notDetermined:
            do {
                let ok = try await center.requestAuthorization(options: [.alert, .sound])
                await refreshAuthorizationStatus()
                return ok
            } catch {
                await refreshAuthorizationStatus()
                return false
            }
        case .denied:
            authorizationStatus = .denied
            return false
        @unknown default:
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Call when saving; respects current settings without always prompting.
    func ensureAuthorizedForScheduling() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorizationIfNeeded()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func cancelPending(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func syncOneTimeReminder(_ reminder: OneTimeReminder) async -> OneTimeReminder {
        #if DEBUG
        AppLog.notifications.debug(
            "syncOneTime begin id=\(reminder.id, privacy: .public) completed=\(reminder.isCompleted) notify=\(reminder.notifyEnabled)"
        )
        #endif
        var r = reminder
        defer {
            #if DEBUG
            AppLog.notifications.debug(
                "syncOneTime leave id=\(r.id, privacy: .public) ids=\(r.notificationIds.count)"
            )
            #endif
        }
        cancelPending(identifiers: r.notificationIds)

        let title = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.notifyEnabled, !title.isEmpty, !r.isCompleted, r.isFireTimeInFuture() else {
            r.notificationIds = []
            return r
        }

        let granted = await ensureAuthorizedForScheduling()
        guard granted else {
            r.notificationIds = []
            r.notifyEnabled = false
            return r
        }

        let id = "onetimer.\(r.id)"
        let content = UNMutableNotificationContent()
        content.title = "定时提醒"
        content.body = title
        content.sound = .default
        content.threadIdentifier = "onetimer"
        content.categoryIdentifier = MiniToolsNotificationCategory.snoozeable
        content.userInfo = ["kind": "one-time-reminder", "reminderId": r.id]

        guard let fire = r.fireDate() else {
            r.notificationIds = []
            return r
        }

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
            r.notificationIds = [id]
        } catch {
            logNotificationAddFailure(error, "oneTime id=\(r.id)")
            r.notificationIds = []
        }
        return r
    }

    func syncAllOneTimeReminders(_ reminders: [OneTimeReminder]) async -> [OneTimeReminder] {
        guard !reminders.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, OneTimeReminder).self, returning: [OneTimeReminder].self) { group in
            for (i, r) in reminders.enumerated() {
                let item = r
                group.addTask {
                    (i, await self.syncOneTimeReminder(item))
                }
            }
            var buf: [(Int, OneTimeReminder)] = []
            buf.reserveCapacity(reminders.count)
            for await pair in group {
                buf.append(pair)
            }
            return buf.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func syncRecurringTask(_ task: RecurringTask) async -> RecurringTask {
        var t = task
        cancelPending(identifiers: t.notificationIds)

        let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.notifyEnabled, !title.isEmpty else {
            t.notificationIds = []
            return t
        }

        let granted = await ensureAuthorizedForScheduling()
        guard granted else {
            t.notificationIds = []
            t.notifyEnabled = false
            return t
        }

        var ids: [String] = []
        let contentBase = UNMutableNotificationContent()
        contentBase.title = "例行任务"
        contentBase.body = title
        contentBase.sound = .default
        contentBase.threadIdentifier = "recurring"
        contentBase.categoryIdentifier = MiniToolsNotificationCategory.snoozeable
        contentBase.userInfo = ["kind": "recurring-task", "taskId": t.id]

        let h = min(23, max(0, t.notifyHour))
        let m = min(59, max(0, t.notifyMinute))

        let cal = Calendar.current
        switch t.recurrence {
        case let .daily(skipWeekends):
            if skipWeekends {
                let dayStarts = LocalCalendarDate.computeNextWeekdayDates(
                    from: Date(),
                    count: 48,
                    calendar: cal
                )
                for (idx, dayStart) in dayStarts.enumerated() {
                    guard let at = cal.date(bySettingHour: h, minute: m, second: 0, of: dayStart),
                          at > Date()
                    else { continue }
                    let dc = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                    let id = "recurring.\(t.id).daily.wd.\(idx)"
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                    let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
                    do {
                        try await center.add(req)
                        ids.append(id)
                    } catch {
                        logNotificationAddFailure(error, "recurring daily.wd \(t.id) idx=\(idx)")
                    }
                }
            } else {
                var dc = DateComponents()
                dc.hour = h
                dc.minute = m
                let id = "recurring.\(t.id).daily"
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
                let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
                do {
                    try await center.add(req)
                    ids.append(id)
                } catch {
                    logNotificationAddFailure(error, "recurring daily \(t.id)")
                }
            }

        case let .weekly(weekdayJs, skipWeekends):
            let jsNorm = ((weekdayJs % 7) + 7) % 7
            let onWeekendChoice = jsNorm == 0 || jsNorm == 6
            if skipWeekends, onWeekendChoice {
                break
            }
            var dc = DateComponents()
            dc.weekday = LocalCalendarDate.appleWeekday(fromJSWeekday: weekdayJs)
            dc.hour = h
            dc.minute = m
            let id = "recurring.\(t.id).weekly"
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
            do {
                try await center.add(req)
                ids.append(id)
            } catch {
                logNotificationAddFailure(error, "recurring weekly \(t.id)")
            }

        case let .monthly(dayOfMonth):
            var dc = DateComponents()
            dc.day = min(31, max(1, dayOfMonth))
            dc.hour = h
            dc.minute = m
            let id = "recurring.\(t.id).monthly"
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
            do {
                try await center.add(req)
                ids.append(id)
            } catch {
                logNotificationAddFailure(error, "recurring monthly \(t.id)")
            }

        case let .yearly(month, dayOfMonth):
            var dc = DateComponents()
            dc.month = min(12, max(1, month))
            dc.day = min(31, max(1, dayOfMonth))
            dc.hour = h
            dc.minute = m
            let id = "recurring.\(t.id).yearly"
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
            do {
                try await center.add(req)
                ids.append(id)
            } catch {
                logNotificationAddFailure(error, "recurring yearly \(t.id)")
            }

        case let .everyNDays(interval, anchorYmd):
            let days = LocalCalendarDate.computeNextDueDatesEveryN(
                intervalDays: interval,
                anchorYmd: anchorYmd,
                from: Date(),
                count: 12,
                calendar: cal
            )
            for (idx, dayStart) in days.enumerated() {
                guard let at = cal.date(
                    bySettingHour: h, minute: m, second: 0, of: dayStart
                ), at > Date() else { continue }

                let dc = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                let id = "recurring.\(t.id).n.\(idx)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
                do {
                    try await center.add(req)
                    ids.append(id)
                } catch {
                    logNotificationAddFailure(error, "recurring nDays \(t.id) idx=\(idx)")
                }
            }
        }

        t.notificationIds = ids
        return t
    }

    func syncHourlyWindowTask(_ task: HourlyWindowTask) async -> HourlyWindowTask {
        var t = task
        cancelPending(identifiers: t.notificationIds)

        let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.notifyEnabled, !title.isEmpty, t.isValidWindow() else {
            t.notificationIds = []
            return t
        }

        let granted = await ensureAuthorizedForScheduling()
        guard granted else {
            t.notificationIds = []
            t.notifyEnabled = false
            return t
        }

        var ids: [String] = []
        let cal = Calendar.current
        let fires = HourlyWindowSchedule.upcomingFireTimes(
            from: Date(),
            task: t,
            calendar: cal,
            maxCount: 28,
            maxDaySpan: 21
        )

        for (idx, fire) in fires.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "时段提醒"
            content.body = title
            content.sound = .default
            content.threadIdentifier = "hourlywindow"
            content.categoryIdentifier = MiniToolsNotificationCategory.hourlyWindow
            content.userInfo = ["kind": "hourly-window-task", "taskId": t.id]

            let dc = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let id = "hourlywin.\(t.id).\(idx)"
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(req)
                ids.append(id)
            } catch {
                logNotificationAddFailure(error, "hourlyWindow \(t.id) idx=\(idx)")
            }
        }

        t.notificationIds = ids
        return t
    }
}
