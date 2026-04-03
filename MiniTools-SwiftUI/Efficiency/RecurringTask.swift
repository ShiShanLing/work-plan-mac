//
//  RecurringTask.swift
//  MiniTools-SwiftUI
//

import Foundation
import MiniToolsCore

/// 循环例行任务：重复规则、提醒时刻、按日完成勾选；可选是否在「今日任务」小组件中展示。
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
    /// When `false`, task stays in the app but is omitted from the Today widget lists / next-up.
    var showInWidget: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, recurrence, notifyEnabled, notifyHour, notifyMinute, notificationIds, createdAt, completedYmds, showInWidget
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
        completedYmds: [String],
        showInWidget: Bool = true
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
        self.showInWidget = showInWidget
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
        showInWidget = try c.decodeIfPresent(Bool.self, forKey: .showInWidget) ?? true
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
        try c.encode(showInWidget, forKey: .showInWidget)
    }

    static func `default`(calendar: Calendar = .current) -> RecurringTask {
        RecurringTask(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))",
            title: "",
            recurrence: .daily(skipWeekends: false),
            notifyEnabled: true,
            notifyHour: 9,
            notifyMinute: 0,
            notificationIds: [],
            createdAt: LocalCalendarDate.localYmd(Date(), calendar: calendar),
            completedYmds: [],
            showInWidget: true
        )
    }

    func isDueOn(_ ref: Date = Date(), calendar: Calendar = .current) -> Bool {
        LocalCalendarDate.isTaskDueOn(recurrence: recurrence, ref: ref, calendar: calendar)
    }

    func isCompleted(on ymd: String) -> Bool {
        completedYmds.contains(ymd)
    }

    /// 创建日当天提醒时刻已过则该日不从「近日待办 / 日历 / 小组件（当 `showInWidget`）」展示（见 `RecurringLateCreationDayFilter`）。
    func shouldOmitFromDisplay(on cellYmd: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        RecurringLateCreationDayFilter.shouldOmitFromDisplay(
            createdAtYmd: createdAt,
            notifyEnabled: notifyEnabled,
            notifyHour: notifyHour,
            notifyMinute: notifyMinute,
            cellDayYmd: cellYmd,
            now: now,
            calendar: calendar
        )
    }

    mutating func setCompleted(_ done: Bool, on ymd: String) {
        if done {
            if !completedYmds.contains(ymd) { completedYmds.append(ymd) }
        } else {
            completedYmds.removeAll { $0 == ymd }
        }
    }
}
