//
//  RecurringTask.swift
//  MiniTools-SwiftUI
//

import Foundation

struct RecurringTask: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var recurrence: Recurrence
    var notifyEnabled: Bool
    var notifyHour: Int
    var notifyMinute: Int
    var notificationIds: [String]
    var createdAt: String
    /// Local YYYY-MM-DD marked done (checklist); does not change recurrence rule.
    var completedYmds: [String]

    static func `default`(calendar: Calendar = .current) -> RecurringTask {
        RecurringTask(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))",
            title: "",
            recurrence: .daily,
            notifyEnabled: false,
            notifyHour: 9,
            notifyMinute: 0,
            notificationIds: [],
            createdAt: LocalCalendarDate.localYmd(Date(), calendar: calendar),
            completedYmds: []
        )
    }

    func isDueOn(_ ref: Date = Date(), calendar: Calendar = .current) -> Bool {
        LocalCalendarDate.isTaskDueOn(recurrence: recurrence, ref: ref, calendar: calendar)
    }

    func isCompleted(on ymd: String) -> Bool {
        completedYmds.contains(ymd)
    }

    mutating func setCompleted(_ done: Bool, on ymd: String) {
        if done {
            if !completedYmds.contains(ymd) { completedYmds.append(ymd) }
        } else {
            completedYmds.removeAll { $0 == ymd }
        }
    }
}

struct DigestPrefs: Codable, Equatable, Sendable {
    var enabled: Bool
    var hour: Int
    var minute: Int

    static let `default` = DigestPrefs(enabled: false, hour: 8, minute: 30)
}
