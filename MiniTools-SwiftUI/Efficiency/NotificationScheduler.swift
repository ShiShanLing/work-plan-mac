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

/// `UNUserNotificationCenterDelegate` 必须由 `NSObject` 实现；若与 `@MainActor` 叠在同一类上，系统可能在任意线程回调 ObjC 路径，易触发异常访问。
/// 将 delegate 单独放在此类中，调度逻辑保留在 `@MainActor` 的 `NotificationScheduler`。
private final class NotificationCenterDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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

    private let center = UNUserNotificationCenter.current()
    private let centerDelegate = NotificationCenterDelegateProxy()

    private init() {
        center.delegate = centerDelegate
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
            r.notificationIds = []
        }
        return r
    }

    func syncAllOneTimeReminders(_ reminders: [OneTimeReminder]) async -> [OneTimeReminder] {
        var out: [OneTimeReminder] = []
        for var r in reminders {
            r = await syncOneTimeReminder(r)
            out.append(r)
        }
        return out
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
        contentBase.userInfo = ["kind": "recurring-task", "taskId": t.id]

        let h = min(23, max(0, t.notifyHour))
        let m = min(59, max(0, t.notifyMinute))

        switch t.recurrence {
        case .daily:
            var dc = DateComponents()
            dc.hour = h
            dc.minute = m
            let id = "recurring.\(t.id).daily"
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
            do {
                try await center.add(req)
                ids.append(id)
            } catch {}

        case let .weekly(weekdayJs):
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
            } catch {}

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
            } catch {}

        case let .everyNDays(interval, anchorYmd):
            let days = LocalCalendarDate.computeNextDueDatesEveryN(
                intervalDays: interval,
                anchorYmd: anchorYmd,
                from: Date(),
                count: 12,
                calendar: Calendar.current
            )
            for (idx, dayStart) in days.enumerated() {
                guard let at = Calendar.current.date(
                    bySettingHour: h, minute: m, second: 0, of: dayStart
                ), at > Date() else { continue }

                let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                let id = "recurring.\(t.id).n.\(idx)"
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let req = UNNotificationRequest(identifier: id, content: contentBase, trigger: trigger)
                do {
                    try await center.add(req)
                    ids.append(id)
                } catch {}
            }
        }

        t.notificationIds = ids
        return t
    }

    func syncDigest(_ prefs: DigestPrefs) async {
        let digestId = "recurring.digest"
        cancelPending(identifiers: [digestId])

        guard prefs.enabled else { return }

        let granted = await ensureAuthorizedForScheduling()
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "今日例行任务"
        content.body = "打开「工作计划」查看今天要做的例行事项"
        content.sound = .default
        content.threadIdentifier = "recurring-digest"
        content.userInfo = ["kind": "recurring-digest"]

        var dc = DateComponents()
        dc.hour = min(23, max(0, prefs.hour))
        dc.minute = min(59, max(0, prefs.minute))
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
        let req = UNNotificationRequest(identifier: digestId, content: content, trigger: trigger)
        try? await center.add(req)
    }
}
