//
//  RecurrenceCalendar.swift
//  MiniTools-SwiftUI
//

import Foundation

enum Recurrence: Codable, Equatable, Sendable {
    case daily
    case everyNDays(intervalDays: Int, anchorDate: String)
    case weekly(weekdayJs: Int)
    case monthly(dayOfMonth: Int)

    private enum CodingKeys: String, CodingKey {
        case kind, intervalDays, anchorDate, weekdayJs, dayOfMonth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "daily":
            self = .daily
        case "everyNDays":
            self = .everyNDays(
                intervalDays: try c.decode(Int.self, forKey: .intervalDays),
                anchorDate: try c.decode(String.self, forKey: .anchorDate)
            )
        case "weekly":
            self = .weekly(weekdayJs: try c.decode(Int.self, forKey: .weekdayJs))
        case "monthly":
            self = .monthly(dayOfMonth: try c.decode(Int.self, forKey: .dayOfMonth))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try c.encode("daily", forKey: .kind)
        case let .everyNDays(intervalDays, anchorDate):
            try c.encode("everyNDays", forKey: .kind)
            try c.encode(intervalDays, forKey: .intervalDays)
            try c.encode(anchorDate, forKey: .anchorDate)
        case let .weekly(weekdayJs):
            try c.encode("weekly", forKey: .kind)
            try c.encode(weekdayJs, forKey: .weekdayJs)
        case let .monthly(dayOfMonth):
            try c.encode("monthly", forKey: .kind)
            try c.encode(dayOfMonth, forKey: .dayOfMonth)
        }
    }
}

enum LocalCalendarDate {
    static func localYmd(_ d: Date, calendar: Calendar = .current) -> String {
        let y = calendar.component(.year, from: d)
        let m = calendar.component(.month, from: d)
        let day = calendar.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, m, day)
    }

    static func parseLocalYmd(_ s: String, calendar: Calendar = .current) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = p[0]
        comps.month = p[1]
        comps.day = p[2]
        comps.hour = 12
        return calendar.date(from: comps)
    }

    static func lastDayOfMonth(year: Int, monthIndex: Int, calendar: Calendar = .current) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = monthIndex + 1
        comps.day = 1
        guard let first = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return 28 }
        return range.count
    }

    static func isMonthlyDueDay(dayOfMonth: Int, ref: Date, calendar: Calendar = .current) -> Bool {
        let y = calendar.component(.year, from: ref)
        let mIdx = calendar.component(.month, from: ref) - 1
        let last = lastDayOfMonth(year: y, monthIndex: mIdx, calendar: calendar)
        let target = min(max(1, dayOfMonth), last)
        return calendar.component(.day, from: ref) == target
    }

    static func isDueEveryNDays(intervalDays: Int, anchorYmd: String, ref: Date, calendar: Calendar = .current) -> Bool {
        guard intervalDays >= 1, let anchor = parseLocalYmd(anchorYmd, calendar: calendar) else { return false }
        let anchorStart = calendar.startOfDay(for: anchor)
        let refStart = calendar.startOfDay(for: ref)
        let diff = calendar.dateComponents([.day], from: anchorStart, to: refStart).day ?? -1
        return diff >= 0 && diff % intervalDays == 0
    }

    static func isTaskDueOn(recurrence: Recurrence, ref: Date, calendar: Calendar = .current) -> Bool {
        switch recurrence {
        case .daily:
            return true
        case let .everyNDays(intervalDays, anchor):
            return isDueEveryNDays(intervalDays: intervalDays, anchorYmd: anchor, ref: ref, calendar: calendar)
        case let .weekly(weekdayJs):
            return calendar.component(.weekday, from: ref) == appleWeekday(fromJSWeekday: weekdayJs)
        case let .monthly(dayOfMonth):
            return isMonthlyDueDay(dayOfMonth: dayOfMonth, ref: ref, calendar: calendar)
        }
    }

    /// JS `Date.getDay()`: 0 = Sunday … 6 = Saturday. Maps to `Calendar.Component.weekday` (1 = Sunday … 7 = Saturday).
    static func appleWeekday(fromJSWeekday js: Int) -> Int {
        js + 1
    }

    static func recurrenceLabel(_ r: Recurrence) -> String {
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        switch r {
        case .daily:
            return "每天"
        case let .everyNDays(interval, _):
            return interval <= 1 ? "每天" : "每 \(interval) 天"
        case let .weekly(weekdayJs):
            let idx = ((weekdayJs % 7) + 7) % 7
            return "每周\(weekdays[idx])"
        case let .monthly(day):
            return "每月 \(day) 日"
        }
    }

    /// Next `count` calendar midnights on or after `from` that match every-N-days rule (aligned to anchor date).
    static func computeNextDueDatesEveryN(
        intervalDays: Int,
        anchorYmd: String,
        from: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard intervalDays >= 1, let anchor = parseLocalYmd(anchorYmd, calendar: calendar) else { return [] }
        let anchorStart = calendar.startOfDay(for: anchor)
        var start = calendar.startOfDay(for: from)
        if start < anchorStart { start = anchorStart }

        var matches: [Date] = []
        var i = 0
        while matches.count < count, i < 800 {
            guard let day = calendar.date(byAdding: .day, value: i, to: start) else { break }
            let dayStart = calendar.startOfDay(for: day)
            let diffDays = calendar.dateComponents([.day], from: anchorStart, to: dayStart).day ?? -1
            if diffDays >= 0, diffDays % intervalDays == 0 {
                matches.append(dayStart)
            }
            i += 1
        }
        return matches
    }
}
