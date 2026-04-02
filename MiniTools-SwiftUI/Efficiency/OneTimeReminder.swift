//
//  OneTimeReminder.swift
//  MiniTools-SwiftUI
//

import Foundation

struct OneTimeReminder: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var dateYmd: String
    var hour: Int
    var minute: Int
    var notifyEnabled: Bool
    var notificationIds: [String]
    var createdAt: String
    /// 用户勾选「已完成」后不再显示在待处理，并取消未触发的通知。
    var isCompleted: Bool
    /// 勾选完成时的本地日历日（`YYYY-MM-DD`），用于历史检索；旧数据可能为空。
    var completedAtYmd: String?

    enum CodingKeys: String, CodingKey {
        case id, title, dateYmd, hour, minute, notifyEnabled, notificationIds, createdAt, isCompleted, completedAtYmd
    }

    init(
        id: String,
        title: String,
        dateYmd: String,
        hour: Int,
        minute: Int,
        notifyEnabled: Bool,
        notificationIds: [String],
        createdAt: String,
        isCompleted: Bool = false,
        completedAtYmd: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dateYmd = dateYmd
        self.hour = hour
        self.minute = minute
        self.notifyEnabled = notifyEnabled
        self.notificationIds = notificationIds
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAtYmd = completedAtYmd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        dateYmd = try c.decode(String.self, forKey: .dateYmd)
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        notifyEnabled = try c.decode(Bool.self, forKey: .notifyEnabled)
        notificationIds = try c.decodeIfPresent([String].self, forKey: .notificationIds) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? LocalCalendarDate.localYmd(Date())
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAtYmd = try c.decodeIfPresent(String.self, forKey: .completedAtYmd)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(dateYmd, forKey: .dateYmd)
        try c.encode(hour, forKey: .hour)
        try c.encode(minute, forKey: .minute)
        try c.encode(notifyEnabled, forKey: .notifyEnabled)
        try c.encode(notificationIds, forKey: .notificationIds)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encodeIfPresent(completedAtYmd, forKey: .completedAtYmd)
    }

    static func newId() -> String {
        "onetime-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
    }

    /// 默认**日期始终为今天**；时刻优先今日 9:00，若已过则用「当前时刻之后」的最近整分（仍落在今天；若已过午夜边缘则退为今日 23:59）。
    static func `default`(calendar: Calendar = .current) -> OneTimeReminder {
        let now = Date()
        let todayYmd = LocalCalendarDate.localYmd(now, calendar: calendar)
        guard let dayStart = LocalCalendarDate.parseLocalYmd(todayYmd, calendar: calendar) else {
            let fd = roundToMinute(now, calendar: calendar)
            return OneTimeReminder(
                id: newId(),
                title: "",
                dateYmd: todayYmd,
                hour: calendar.component(.hour, from: fd),
                minute: calendar.component(.minute, from: fd),
                notifyEnabled: true,
                notificationIds: [],
                createdAt: LocalCalendarDate.localYmd(Date(), calendar: calendar),
                isCompleted: false
            )
        }

        var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = 9
        comps.minute = 0
        comps.second = 0
        let nineToday = calendar.date(from: comps) ?? now

        let fire: Date
        if nineToday > now {
            fire = nineToday
        } else {
            let step = calendar.date(byAdding: .minute, value: 1, to: now) ?? now
            var candidate = roundToMinute(step, calendar: calendar)
            if !calendar.isDate(candidate, inSameDayAs: dayStart) || candidate <= now {
                comps.hour = 23
                comps.minute = 59
                comps.second = 0
                candidate = calendar.date(from: comps) ?? candidate
            }
            fire = candidate
        }

        let rounded = roundToMinute(fire, calendar: calendar)
        let h = calendar.component(.hour, from: rounded)
        let mi = calendar.component(.minute, from: rounded)
        return OneTimeReminder(
            id: newId(),
            title: "",
            dateYmd: todayYmd,
            hour: h,
            minute: mi,
            notifyEnabled: true,
            notificationIds: [],
            createdAt: LocalCalendarDate.localYmd(Date(), calendar: calendar),
            isCompleted: false
        )
    }

    /// 日历上选中某日时新建定时提醒：日期为该日，时刻默认当天 9:00（可在编辑页修改）。
    /// 从需求清单/子任务预填：日期取清单截止或开始日，否则今日；标题为「清单 · 子任务」或仅清单名。
    static func draftFromChecklistHint(
        checklistTitle: String,
        subtaskTitle: String?,
        dateYmd: String,
        calendar: Calendar = .current
    ) -> OneTimeReminder {
        var r = newDraftForCalendarDay(ymd: dateYmd, calendar: calendar)
        let c = checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = subtaskTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !s.isEmpty {
            if c.isEmpty {
                r.title = s
            } else {
                r.title = "\(c) · \(s)"
            }
        } else {
            r.title = c.isEmpty ? "需求清单" : c
        }
        return r
    }

    static func newDraftForCalendarDay(ymd: String, calendar: Calendar = .current) -> OneTimeReminder {
        guard let dayStart = LocalCalendarDate.parseLocalYmd(ymd, calendar: calendar) else {
            return Self.default(calendar: calendar)
        }
        var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = 9
        comps.minute = 0
        comps.second = 0
        let fire = calendar.date(from: comps) ?? dayStart
        let rounded = roundToMinute(fire, calendar: calendar)
        let outYmd = LocalCalendarDate.localYmd(rounded, calendar: calendar)
        let h = calendar.component(.hour, from: rounded)
        let m = calendar.component(.minute, from: rounded)
        return OneTimeReminder(
            id: newId(),
            title: "",
            dateYmd: outYmd,
            hour: h,
            minute: m,
            notifyEnabled: true,
            notificationIds: [],
            createdAt: LocalCalendarDate.localYmd(Date(), calendar: calendar),
            isCompleted: false,
            completedAtYmd: nil
        )
    }

    static func roundToMinute(_ d: Date, calendar: Calendar) -> Date {
        var c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        c.second = 0
        c.nanosecond = 0
        return calendar.date(from: c) ?? d
    }

    func fireDate(calendar: Calendar = .current) -> Date? {
        let p = dateYmd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = DateComponents()
        c.year = p[0]
        c.month = p[1]
        c.day = p[2]
        c.hour = hour
        c.minute = minute
        c.second = 0
        return calendar.date(from: c)
    }

    func isFireTimeInFuture(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let t = fireDate(calendar: calendar)?.timeIntervalSince1970 else { return false }
        return t > now.timeIntervalSince1970
    }

    func formatFireSummary() -> String {
        String(format: "%@ %02d:%02d", dateYmd, hour, minute)
    }

    /// 是否安排在「今天」本地日期（含已到期未勾选）。
    func isScheduledForToday(calendar: Calendar = .current) -> Bool {
        dateYmd == LocalCalendarDate.localYmd(Date(), calendar: calendar)
    }
}
