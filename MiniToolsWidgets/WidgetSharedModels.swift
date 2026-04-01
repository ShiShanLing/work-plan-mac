//
//  WidgetSharedModels.swift
//  MiniToolsWidgetsExtension
//
//  与主应用 JSON 字段一致（独立 target，故复制一份解码模型）。
//

import Foundation

enum WidgetAppGroup {
    static let identifier = "group.com.MiniTools.www.MiniTools-SwiftUI"
}

// MARK: - Recurrence (copy)

enum WGRecurrence: Codable, Equatable {
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
        case "daily": self = .daily
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
        case .daily: try c.encode("daily", forKey: .kind)
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

enum WGCalendar {
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

    static func isTaskDueOn(recurrence: WGRecurrence, ref: Date, calendar: Calendar = .current) -> Bool {
        switch recurrence {
        case .daily: return true
        case let .everyNDays(intervalDays, anchor):
            return isDueEveryNDays(intervalDays: intervalDays, anchorYmd: anchor, ref: ref, calendar: calendar)
        case let .weekly(weekdayJs):
            // 与主应用 `LocalCalendarDate.appleWeekday(fromJSWeekday:)` 一致：JS 一周 0…6，规范化后再 +1 对齐 `Calendar.Component.weekday`（1=周日…）。
            let js = ((weekdayJs % 7) + 7) % 7
            return calendar.component(.weekday, from: ref) == js + 1
        case let .monthly(dayOfMonth):
            return isMonthlyDueDay(dayOfMonth: dayOfMonth, ref: ref, calendar: calendar)
        }
    }

    static func recurrenceLabel(_ r: WGRecurrence) -> String {
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
}

struct WGOneTimeReminder: Codable, Identifiable {
    var id: String
    var title: String
    var dateYmd: String
    var hour: Int
    var minute: Int
    var notifyEnabled: Bool
    var notificationIds: [String]
    var createdAt: String
    var isCompleted: Bool
    var completedAtYmd: String?

    enum CodingKeys: String, CodingKey {
        case id, title, dateYmd, hour, minute, notifyEnabled, notificationIds, createdAt, isCompleted, completedAtYmd
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
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? WGCalendar.localYmd(Date())
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

    func fireSummary() -> String {
        String(format: "%@ %02d:%02d", dateYmd, hour, minute)
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
}

struct WGRecurringTask: Codable, Identifiable {
    var id: String
    var title: String
    var recurrence: WGRecurrence
    var notifyEnabled: Bool
    var notifyHour: Int
    var notifyMinute: Int
    var notificationIds: [String]
    var createdAt: String
    var completedYmds: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, recurrence, notifyEnabled, notifyHour, notifyMinute, notificationIds, createdAt, completedYmds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        recurrence = try c.decode(WGRecurrence.self, forKey: .recurrence)
        notifyEnabled = try c.decode(Bool.self, forKey: .notifyEnabled)
        notifyHour = try c.decode(Int.self, forKey: .notifyHour)
        notifyMinute = try c.decode(Int.self, forKey: .notifyMinute)
        notificationIds = try c.decodeIfPresent([String].self, forKey: .notificationIds) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? WGCalendar.localYmd(Date())
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
}

// MARK: - IO

enum TodayWidgetIO {
    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// 与 `LocalJSONStore` 一致：优先 App Group 下 `MiniToolsData`，否则回退 `Application Support/MiniTools-SwiftUI`（主应用未开 Group 或迁移前）。
    private static func jsonURLs(fileName: String) -> [URL] {
        var urls: [URL] = []
        if let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetAppGroup.identifier) {
            let dir = root.appending(path: "MiniToolsData", directoryHint: .isDirectory)
            urls.append(dir.appending(path: fileName, directoryHint: .notDirectory))
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appending(path: "MiniTools-SwiftUI", directoryHint: .isDirectory)
            urls.append(dir.appending(path: fileName, directoryHint: .notDirectory))
        }
        return urls
    }

    /// 对 **数组** JSON：优先返回**第一个非空**解码结果。若 Group 里是 `[]` 仍会继续尝试 Application Support（避免误判为无数据）。
    private static func loadJSONArray<Element: Decodable>(_ type: [Element].Type, fileName: String) -> [Element] {
        var fallbackEmpty: [Element]?
        for url in jsonURLs(fileName: fileName) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            guard let v = try? decoder.decode(type, from: data) else { continue }
            if !v.isEmpty { return v }
            if fallbackEmpty == nil { fallbackEmpty = v }
        }
        return fallbackEmpty ?? []
    }

    static var dataDirectory: URL? {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetAppGroup.identifier)
        else { return nil }
        let dir = root.appending(path: "MiniToolsData", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path()) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func loadOneTimes() -> [WGOneTimeReminder] {
        loadJSONArray([WGOneTimeReminder].self, fileName: "one_time_reminders.json")
    }

    static func saveOneTimes(_ items: [WGOneTimeReminder]) throws {
        guard let dir = dataDirectory else { throw CocoaError(.fileNoSuchFile) }
        let url = dir.appending(path: "one_time_reminders.json", directoryHint: .notDirectory)
        let data = try encoder.encode(items)
        try data.write(to: url, options: .atomic)
    }

    static func loadRecurring() -> [WGRecurringTask] {
        loadJSONArray([WGRecurringTask].self, fileName: "recurring_tasks.json")
    }

    static func saveRecurring(_ items: [WGRecurringTask]) throws {
        guard let dir = dataDirectory else { throw CocoaError(.fileNoSuchFile) }
        let url = dir.appending(path: "recurring_tasks.json", directoryHint: .notDirectory)
        let data = try encoder.encode(items)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - 今日行（小组件用）

struct TodayRowData: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let isOneTime: Bool
    let rawId: String
    let todayYmd: String
}

/// 小组件「下一次」区块所用的预告信息（主应用逻辑对齐：按时间取最早一条）。
struct NextUpTaskInfo {
    let title: String
    let detail: String
    let isOneTime: Bool
    let rawId: String
    /// 例行任务勾选链接必填；一次性可填 `dateYmd` 备用。
    let ymdForRecurring: String
}

enum TodayWidgetRowLoader {
    /// 与主应用日历页一致，避免小组件与 App 因 `Calendar.current` 差异导致「今日」判定不一致。
    /// 与用户「日期设置」一致；自建 gregorian 曾与 `Calendar.current` 在个别环境下差一天。
    private static var widgetCalendar: Calendar {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "zh-Hans")
        return cal
    }

    /// 与 `loadNextUpcoming` 使用同一时间基准，避免跨午夜或单次调用内时钟不一致。
    /// 「下一次」始终计算：`rows` 中已有条目（今日待办）通过 `skip` 排除，避免与列表重复；今日全完成且 `rows` 为空时仍可看到下一档何时、何事。
    static func loadEntry(at now: Date) -> (rows: [TodayRowData], nextUp: NextUpTaskInfo?) {
        let cal = widgetCalendar
        let oneTimes = TodayWidgetIO.loadOneTimes()
        let recurring = TodayWidgetIO.loadRecurring()
        let rows = makeRows(now: now, calendar: cal, oneTimes: oneTimes, recurring: recurring)
        var skipOneTimeIds: Set<String> = []
        var skipRecurringDayKeys: Set<String> = []
        for row in rows {
            if row.isOneTime {
                skipOneTimeIds.insert(row.rawId)
            } else {
                skipRecurringDayKeys.insert("\(row.rawId)|\(row.todayYmd)")
            }
        }
        let next = computeNextUpcoming(
            now: now,
            calendar: cal,
            oneTimes: oneTimes,
            recurring: recurring,
            skipOneTimeIds: skipOneTimeIds,
            skipRecurringDayKeys: skipRecurringDayKeys
        )
        return (rows, next)
    }

    static func loadRows(now: Date, calendar cal: Calendar) -> [TodayRowData] {
        makeRows(
            now: now,
            calendar: cal,
            oneTimes: TodayWidgetIO.loadOneTimes(),
            recurring: TodayWidgetIO.loadRecurring()
        )
    }

    private static func makeRows(
        now: Date,
        calendar cal: Calendar,
        oneTimes: [WGOneTimeReminder],
        recurring: [WGRecurringTask]
    ) -> [TodayRowData] {
        let today = WGCalendar.localYmd(now, calendar: cal)
        var rows: [TodayRowData] = []

        let todayOne = oneTimes
            .filter { !$0.isCompleted && $0.dateYmd == today }
            .sorted {
                if $0.hour != $1.hour { return $0.hour < $1.hour }
                return $0.minute < $1.minute
            }
        for o in todayOne {
            rows.append(TodayRowData(
                id: "o-\(o.id)",
                title: o.title.isEmpty ? "（无标题）" : o.title,
                subtitle: "定时 · \(o.fireSummary())",
                isOneTime: true,
                rawId: o.id,
                todayYmd: today
            ))
        }

        let recs = recurring
            .filter {
                WGCalendar.isTaskDueOn(recurrence: $0.recurrence, ref: now, calendar: cal) && !$0.completedYmds.contains(today)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        for t in recs {
            rows.append(TodayRowData(
                id: "r-\(t.id)",
                title: t.title.isEmpty ? "（无标题）" : t.title,
                subtitle: "例行 · \(WGCalendar.recurrenceLabel(t.recurrence))",
                isOneTime: false,
                rawId: t.id,
                todayYmd: today
            ))
        }

        return rows
    }

    private static let upcomingScanDays = 1200

    /// 未完成的一次性提醒（按触发时刻）或例行任务（下一到期日且该日未勾选）中时间上更早的一条。
    static func loadNextUpcoming(now: Date = Date(), calendar cal: Calendar? = nil) -> NextUpTaskInfo? {
        let c = cal ?? widgetCalendar
        return computeNextUpcoming(
            now: now,
            calendar: c,
            oneTimes: TodayWidgetIO.loadOneTimes(),
            recurring: TodayWidgetIO.loadRecurring(),
            skipOneTimeIds: [],
            skipRecurringDayKeys: []
        )
    }

    private static func computeNextUpcoming(
        now: Date,
        calendar c: Calendar,
        oneTimes allOne: [WGOneTimeReminder],
        recurring allRec: [WGRecurringTask],
        skipOneTimeIds: Set<String> = [],
        skipRecurringDayKeys: Set<String> = []
    ) -> NextUpTaskInfo? {
        let startToday = c.startOfDay(for: now)

        let oneTimes = allOne.filter { !$0.isCompleted }
        var bestOne: WGOneTimeReminder?
        var bestOneFire: Date?

        for o in oneTimes {
            guard !skipOneTimeIds.contains(o.id) else { continue }
            guard let fd = o.fireDate(calendar: c) else { continue }
            if fd >= now {
                if bestOneFire == nil || fd < bestOneFire! {
                    bestOne = o
                    bestOneFire = fd
                }
            }
        }
        if bestOneFire == nil {
            for o in oneTimes {
                guard !skipOneTimeIds.contains(o.id) else { continue }
                guard let fd = o.fireDate(calendar: c) else { continue }
                if bestOneFire == nil || fd < bestOneFire! {
                    bestOne = o
                    bestOneFire = fd
                }
            }
        }

        var bestRecTask: WGRecurringTask?
        var bestRecDate: Date?
        var bestRecYmd: String?

        for t in allRec {
            guard let hit = firstPendingOccurrence(
                of: t,
                fromStartOfToday: startToday,
                calendar: c,
                maxDays: upcomingScanDays,
                skipRecurringDayKeys: skipRecurringDayKeys
            )
            else { continue }
            if bestRecDate == nil || hit.sortDate < bestRecDate! {
                bestRecTask = t
                bestRecDate = hit.sortDate
                bestRecYmd = hit.ymd
            }
        }

        guard bestOneFire != nil || bestRecDate != nil else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd EEEE"

        let preferOneTime: Bool
        if let odt = bestOneFire, let rdt = bestRecDate {
            preferOneTime = odt <= rdt
        } else {
            preferOneTime = bestRecDate == nil
        }

        if preferOneTime, let o = bestOne, let ft = bestOneFire {
            let dayLabel = formatter.string(from: ft)
            let timeStr = String(format: "%02d:%02d", o.hour, o.minute)
            return NextUpTaskInfo(
                title: o.title.isEmpty ? "（无标题）" : o.title,
                detail: "\(dayLabel) · \(timeStr) · 定时",
                isOneTime: true,
                rawId: o.id,
                ymdForRecurring: o.dateYmd
            )
        }

        if let r = bestRecTask, let rt = bestRecDate, let ymd = bestRecYmd {
            let timeStr = String(format: "%02d:%02d", r.notifyHour, r.notifyMinute)
            let dayLabel = formatter.string(from: rt)
            let sched = r.notifyEnabled ? "提醒 \(timeStr)" : "无时间提醒"
            return NextUpTaskInfo(
                title: r.title.isEmpty ? "（无标题）" : r.title,
                detail: "\(dayLabel) · \(sched) · \(WGCalendar.recurrenceLabel(r.recurrence))",
                isOneTime: false,
                rawId: r.id,
                ymdForRecurring: ymd
            )
        }

        return nil
    }

    private static func firstPendingOccurrence(
        of task: WGRecurringTask,
        fromStartOfToday startToday: Date,
        calendar cal: Calendar,
        maxDays: Int,
        skipRecurringDayKeys: Set<String>
    ) -> (sortDate: Date, ymd: String)? {
        for offset in 0 ..< maxDays {
            guard let d = cal.date(byAdding: .day, value: offset, to: startToday) else { continue }
            let ymd = WGCalendar.localYmd(d, calendar: cal)
            guard WGCalendar.isTaskDueOn(recurrence: task.recurrence, ref: d, calendar: cal) else { continue }
            guard !task.completedYmds.contains(ymd) else { continue }
            guard !skipRecurringDayKeys.contains("\(task.id)|\(ymd)") else { continue }
            let dayStart = cal.startOfDay(for: d)
            var comps = cal.dateComponents([.year, .month, .day], from: dayStart)
            comps.hour = task.notifyHour
            comps.minute = task.notifyMinute
            comps.second = 0
            let sortDate = cal.date(from: comps) ?? dayStart
            return (sortDate, ymd)
        }
        return nil
    }
}
