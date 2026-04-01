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

    enum CodingKeys: String, CodingKey {
        case id, title, recurrence, notifyEnabled, notifyHour, notifyMinute, notificationIds, createdAt, completedYmds
    }

    init(
        id: String,
        title: String,
        recurrence: Recurrence,
        notifyEnabled: Bool,
        notifyHour: Int,
        notifyMinute: Int,
        notificationIds: [String],
        createdAt: String,
        completedYmds: [String]
    ) {
        self.id = id
        self.title = title
        self.recurrence = recurrence
        self.notifyEnabled = notifyEnabled
        self.notifyHour = notifyHour
        self.notifyMinute = notifyMinute
        self.notificationIds = notificationIds
        self.createdAt = createdAt
        self.completedYmds = completedYmds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        recurrence = try c.decode(Recurrence.self, forKey: .recurrence)
        notifyEnabled = try c.decodeIfPresent(Bool.self, forKey: .notifyEnabled) ?? false
        notifyHour = try c.decodeIfPresent(Int.self, forKey: .notifyHour) ?? 9
        notifyMinute = try c.decodeIfPresent(Int.self, forKey: .notifyMinute) ?? 0
        notificationIds = try c.decodeIfPresent([String].self, forKey: .notificationIds) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? LocalCalendarDate.localYmd(Date())
        completedYmds = try c.decodeIfPresent([String].self, forKey: .completedYmds) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(recurrence, forKey: .recurrence)
        try c.encode(notifyEnabled, forKey: .notifyEnabled)
        try c.encode(notifyHour, forKey: .notifyHour)
        try c.encode(notifyMinute, forKey: .notifyMinute)
        try c.encode(notificationIds, forKey: .notificationIds)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(completedYmds, forKey: .completedYmds)
    }

    static func `default`(calendar: Calendar = .current) -> RecurringTask {
        RecurringTask(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))",
            title: "",
            recurrence: .daily(skipWeekends: false),
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
