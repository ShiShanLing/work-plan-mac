//
//  HourlyWindowTask.swift
//  MiniTools-SwiftUI
//

import Foundation
import MiniToolsCore

/// 在时间窗内按固定间隔（分钟）重复提醒。跨日由 `windowEndDayOffset` **显式**指定：0 表示结束在与开始同一天；1 表示结束在开始的下一日历日（与用户在日期选择器里选的相对关系一致）。
struct HourlyWindowTask: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    /// 提醒间隔，分钟，1…1440。
    var intervalMinutes: Int
    var windowStartHour: Int
    var windowStartMinute: Int
    var windowEndHour: Int
    var windowEndMinute: Int
    /// 相对开始日的日历偏移：0 = 结束在同一天；1 = 结束在次日（前台与日期选择器一致，不做「钟点大小」猜测）。
    var windowEndDayOffset: Int
    /// 为 `true` 时仅在周一至周五（按 `Calendar.isDateInWeekend` 排除周末）生效。
    var weekdaysOnly: Bool
    var notifyEnabled: Bool
    var notificationIds: [String]
    var createdAt: String
    /// 将「当天全部时段」标为已处理（与例行任务的「某日完成」类似）。
    var completedYmds: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, intervalMinutes, intervalHours
        case windowStartHour, windowStartMinute, windowEndHour, windowEndMinute
        case windowEndDayOffset
        case weekdaysOnly, notifyEnabled, notificationIds, createdAt, completedYmds
    }

    init(
        id: String,
        title: String,
        intervalMinutes: Int,
        windowStartHour: Int,
        windowStartMinute: Int,
        windowEndHour: Int,
        windowEndMinute: Int,
        windowEndDayOffset: Int = 0,
        weekdaysOnly: Bool,
        notifyEnabled: Bool,
        notificationIds: [String],
        createdAt: String,
        completedYmds: [String]
    ) {
        self.id = id
        self.title = title
        self.intervalMinutes = intervalMinutes
        self.windowStartHour = windowStartHour
        self.windowStartMinute = windowStartMinute
        self.windowEndHour = windowEndHour
        self.windowEndMinute = windowEndMinute
        self.windowEndDayOffset = windowEndDayOffset
        self.weekdaysOnly = weekdaysOnly
        self.notifyEnabled = notifyEnabled
        self.notificationIds = notificationIds
        self.createdAt = createdAt
        self.completedYmds = completedYmds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        if let m = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) {
            intervalMinutes = m
        } else if let h = try c.decodeIfPresent(Int.self, forKey: .intervalHours) {
            intervalMinutes = max(1, min(1440, h * 60))
        } else {
            intervalMinutes = 60
        }
        windowStartHour = try c.decode(Int.self, forKey: .windowStartHour)
        windowStartMinute = try c.decode(Int.self, forKey: .windowStartMinute)
        windowEndHour = try c.decode(Int.self, forKey: .windowEndHour)
        windowEndMinute = try c.decode(Int.self, forKey: .windowEndMinute)
        if let off = try c.decodeIfPresent(Int.self, forKey: .windowEndDayOffset) {
            windowEndDayOffset = off == 1 ? 1 : 0
        } else {
            let a = windowStartHour * 60 + windowStartMinute
            let b = windowEndHour * 60 + windowEndMinute
            windowEndDayOffset = a > b ? 1 : 0
        }
        weekdaysOnly = try c.decode(Bool.self, forKey: .weekdaysOnly)
        notifyEnabled = try c.decode(Bool.self, forKey: .notifyEnabled)
        notificationIds = try c.decodeIfPresent([String].self, forKey: .notificationIds) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? LocalCalendarDate.localYmd(Date())
        completedYmds = try c.decodeIfPresent([String].self, forKey: .completedYmds) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(intervalMinutes, forKey: .intervalMinutes)
        try c.encode(windowStartHour, forKey: .windowStartHour)
        try c.encode(windowStartMinute, forKey: .windowStartMinute)
        try c.encode(windowEndHour, forKey: .windowEndHour)
        try c.encode(windowEndMinute, forKey: .windowEndMinute)
        try c.encode(windowEndDayOffset, forKey: .windowEndDayOffset)
        try c.encode(weekdaysOnly, forKey: .weekdaysOnly)
        try c.encode(notifyEnabled, forKey: .notifyEnabled)
        try c.encode(notificationIds, forKey: .notificationIds)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(completedYmds, forKey: .completedYmds)
    }

    static func `default`(calendar: Calendar = .current) -> HourlyWindowTask {
        HourlyWindowTask(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))",
            title: "",
            intervalMinutes: 60,
            windowStartHour: 9,
            windowStartMinute: 0,
            windowEndHour: 17,
            windowEndMinute: 30,
            windowEndDayOffset: 0,
            weekdaysOnly: true,
            notifyEnabled: true,
            notificationIds: [],
            createdAt: LocalCalendarDate.localYmd(Date(), calendar: calendar),
            completedYmds: []
        )
    }

    var hourlyWindowConfig: HourlyWindowConfig {
        HourlyWindowConfig(
            intervalMinutes: intervalMinutes,
            windowStartHour: windowStartHour,
            windowStartMinute: windowStartMinute,
            windowEndHour: windowEndHour,
            windowEndMinute: windowEndMinute,
            windowEndDayOffset: windowEndDayOffset,
            weekdaysOnly: weekdaysOnly
        )
    }

    func isValidWindow(calendar cal: Calendar = .current) -> Bool {
        HourlyWindowScheduling.isValidWindow(hourlyWindowConfig, calendar: cal)
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

    func summaryScheduleLabel() -> String {
        HourlyWindowScheduling.scheduleLabel(
            intervalMinutes: intervalMinutes,
            startHour: windowStartHour,
            startMinute: windowStartMinute,
            endHour: windowEndHour,
            endMinute: windowEndMinute,
            windowEndDayOffset: windowEndDayOffset,
            weekdaysOnly: weekdaysOnly
        )
    }

    /// 当天是否应该出现在待办（不看完成态）。
    func isActive(on dayDate: Date, calendar: Calendar = .current) -> Bool {
        HourlyWindowScheduling.appliesToDay(weekdaysOnly: weekdaysOnly, date: dayDate, calendar: calendar)
    }
}

// MARK: - 通知 / 其它调用方

enum HourlyWindowSchedule {
    static func slotDates(on dayStart: Date, calendar cal: Calendar, task: HourlyWindowTask) -> [Date] {
        HourlyWindowScheduling.slotDates(on: dayStart, calendar: cal, config: task.hourlyWindowConfig)
    }

    static func nextFire(after from: Date, task: HourlyWindowTask, calendar cal: Calendar, scanDays: Int = 21) -> Date? {
        HourlyWindowScheduling.nextFire(after: from, config: task.hourlyWindowConfig, calendar: cal, scanDays: scanDays)
    }

    static func upcomingFireTimes(
        from: Date,
        task: HourlyWindowTask,
        calendar cal: Calendar,
        maxCount: Int,
        maxDaySpan: Int
    ) -> [Date] {
        let boosted = max(maxCount * 4, maxCount + 16)
        let raw = HourlyWindowScheduling.upcomingFireTimes(
            from: from,
            config: task.hourlyWindowConfig,
            calendar: cal,
            maxCount: boosted,
            maxDaySpan: maxDaySpan
        )
        var out: [Date] = []
        out.reserveCapacity(maxCount)
        for d in raw {
            let ymd = LocalCalendarDate.localYmd(d, calendar: cal)
            if task.isCompleted(on: ymd) { continue }
            out.append(d)
            if out.count == maxCount { break }
        }
        return out
    }
}
