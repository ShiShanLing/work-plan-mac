import Foundation

/// 时段提醒的日历计算（单一实现，供主应用与 Widget 共用）。
public enum HourlyWindowScheduling: Sendable {
    /// 用于校验窗口长度的参考日：取年中非边界日，降低夏令时切日附近的歧义（与「今天」无关的重复规则仍应稳定）。
    private static func validationDayStart(calendar cal: Calendar) -> Date {
        var dc = DateComponents()
        dc.year = 2000
        dc.month = 6
        dc.day = 15
        let mid = cal.date(from: dc) ?? Date(timeIntervalSince1970: 963)
        return cal.startOfDay(for: mid)
    }

    public static func appliesToDay(weekdaysOnly: Bool, date: Date, calendar: Calendar) -> Bool {
        if weekdaysOnly, calendar.isDateInWeekend(date) { return false }
        return true
    }

  

    public static func isValidWindow(_ config: HourlyWindowConfig, calendar cal: Calendar) -> Bool {
        guard (1 ... 1440).contains(config.intervalMinutes) else { return false }
        guard config.windowEndDayOffset == 0 || config.windowEndDayOffset == 1 else { return false }
        guard (0 ... 23).contains(config.windowStartHour), (0 ... 59).contains(config.windowStartMinute),
              (0 ... 23).contains(config.windowEndHour), (0 ... 59).contains(config.windowEndMinute)
        else { return false }
        let ref = validationDayStart(calendar: cal)
        guard let tOpen = cal.date(
            bySettingHour: config.windowStartHour,
            minute: config.windowStartMinute,
            second: 0,
            of: ref
        ),
            let endDay = cal.date(byAdding: .day, value: config.windowEndDayOffset, to: ref),
            let tClose = cal.date(
                bySettingHour: config.windowEndHour,
                minute: config.windowEndMinute,
                second: 0,
                of: endDay
            )
        else { return false }
        return tClose > tOpen
    }

    public static func slotDates(on dayStart: Date, calendar cal: Calendar, config: HourlyWindowConfig) -> [Date] {
        guard isValidWindow(config, calendar: cal) else { return [] }
        guard appliesToDay(weekdaysOnly: config.weekdaysOnly, date: dayStart, calendar: cal) else { return [] }

        let step = config.intervalMinutes
        let sh = config.windowStartHour
        let sm = config.windowStartMinute
        let eh = config.windowEndHour
        let em = config.windowEndMinute
        let off = config.windowEndDayOffset

        let prevDay = cal.date(byAdding: .day, value: -1, to: dayStart)!
        let dayEndExclusive = cal.date(byAdding: .day, value: 1, to: dayStart)!

        var out: [Date] = []

        for anchorDay in [prevDay, dayStart] {
            guard appliesToDay(weekdaysOnly: config.weekdaysOnly, date: anchorDay, calendar: cal) else { continue }
            guard let tOpen = cal.date(bySettingHour: sh, minute: sm, second: 0, of: anchorDay),
                  let endDay = cal.date(byAdding: .day, value: off, to: anchorDay),
                  let tClose = cal.date(bySettingHour: eh, minute: em, second: 0, of: endDay)
            else { continue }
            guard tClose > tOpen else { continue }

            var cur = tOpen
            while cur <= tClose {
                if cur >= dayStart, cur < dayEndExclusive {
                    out.append(cur)
                }
                guard let nxt = cal.date(byAdding: .minute, value: step, to: cur) else { break }
                cur = nxt
            }
        }

        return out.sorted()
    }

    public static func scheduleLabel(
        intervalMinutes: Int,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        windowEndDayOffset: Int,
        weekdaysOnly: Bool
    ) -> String {
        let startClock = String(format: "%02d:%02d", startHour, startMinute)
        let endClock = String(format: "%02d:%02d", endHour, endMinute)
        let fmt = windowEndDayOffset >= 1
            ? "\(startClock)–次日 \(endClock)"
            : "\(startClock)–\(endClock)"
        let cadence: String
        if intervalMinutes >= 60, intervalMinutes % 60 == 0 {
            let h = intervalMinutes / 60
            cadence = h <= 1 ? "每 1 小时" : "每 \(h) 小时"
        } else {
            cadence = "每 \(intervalMinutes) 分钟"
        }
        let w = weekdaysOnly ? " · 仅工作日" : ""
        return "\(cadence) · \(fmt)\(w)"
    }

    public static func nextFire(
        after from: Date,
        config: HourlyWindowConfig,
        calendar cal: Calendar,
        scanDays: Int = 21
    ) -> Date? {
        guard isValidWindow(config, calendar: cal) else { return nil }
        let day0 = cal.startOfDay(for: from)
        var best: Date?
        for offset in 0 ..< scanDays {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: day0) else { continue }
            let slots = slotDates(
                on: cal.startOfDay(for: dayStart),
                calendar: cal,
                config: config
            )
            for d in slots where d > from {
                if best == nil || d < best! { best = d }
            }
        }
        return best
    }

    public static func upcomingFireTimes(
        from: Date,
        config: HourlyWindowConfig,
        calendar cal: Calendar,
        maxCount: Int,
        maxDaySpan: Int
    ) -> [Date] {
        guard isValidWindow(config, calendar: cal), maxCount > 0 else { return [] }
        var out: [Date] = []
        let startDay = cal.startOfDay(for: from)
        for offset in 0 ..< maxDaySpan {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let dayMidnight = cal.startOfDay(for: dayStart)
            let slots = slotDates(on: dayMidnight, calendar: cal, config: config)
            for d in slots.sorted() where d > from {
                out.append(d)
                if out.count >= maxCount { return out }
            }
        }
        return out
    }
}
