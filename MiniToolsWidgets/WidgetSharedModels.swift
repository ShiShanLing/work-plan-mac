//
//  WidgetSharedModels.swift
//  MiniToolsWidgetsExtension
//
//  与主应用 JSON 字段一致（独立 target，故复制一份解码模型）。时段排期逻辑见 `MiniToolsCore.HourlyWindowScheduling`。
//

import Foundation
import MiniToolsCore
import OSLog

private enum TodayWidgetDebugLog {
    static let log = Logger(subsystem: "com.MiniTools.www.MiniTools-SwiftUI", category: "TodayWidget")
}

/// 小组件扩展内使用的 App Group 标识（须与主 target 一致）。
enum WidgetAppGroup {
    static let identifier = "group.com.MiniTools.www.MiniTools-SwiftUI"
}

// MARK: - Recurrence (copy)

/// 与主应用 `Recurrence` JSON 形状一致的重复规则（独立模块拷贝）。
enum WGRecurrence: Codable, Equatable {
    case daily(skipWeekends: Bool)
    case everyNDays(intervalDays: Int, anchorDate: String)
    case weekly(weekdayJs: Int, skipWeekends: Bool)
    case monthly(dayOfMonth: Int)
    case yearly(month: Int, dayOfMonth: Int)

    private enum CodingKeys: String, CodingKey {
        case kind, intervalDays, anchorDate, weekdayJs, dayOfMonth, month, skipWeekends
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "daily":
            self = .daily(skipWeekends: try c.decodeIfPresent(Bool.self, forKey: .skipWeekends) ?? false)
        case "everyNDays":
            self = .everyNDays(
                intervalDays: try c.decode(Int.self, forKey: .intervalDays),
                anchorDate: try c.decode(String.self, forKey: .anchorDate)
            )
        case "weekly":
            self = .weekly(
                weekdayJs: try c.decode(Int.self, forKey: .weekdayJs),
                skipWeekends: try c.decodeIfPresent(Bool.self, forKey: .skipWeekends) ?? false
            )
        case "monthly":
            self = .monthly(dayOfMonth: try c.decode(Int.self, forKey: .dayOfMonth))
        case "yearly":
            self = .yearly(
                month: try c.decode(Int.self, forKey: .month),
                dayOfMonth: try c.decode(Int.self, forKey: .dayOfMonth)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .daily(skipWeekends):
            try c.encode("daily", forKey: .kind)
            try c.encode(skipWeekends, forKey: .skipWeekends)
        case let .everyNDays(intervalDays, anchorDate):
            try c.encode("everyNDays", forKey: .kind)
            try c.encode(intervalDays, forKey: .intervalDays)
            try c.encode(anchorDate, forKey: .anchorDate)
        case let .weekly(weekdayJs, skipWeekends):
            try c.encode("weekly", forKey: .kind)
            try c.encode(weekdayJs, forKey: .weekdayJs)
            try c.encode(skipWeekends, forKey: .skipWeekends)
        case let .monthly(dayOfMonth):
            try c.encode("monthly", forKey: .kind)
            try c.encode(dayOfMonth, forKey: .dayOfMonth)
        case let .yearly(month, dayOfMonth):
            try c.encode("yearly", forKey: .kind)
            try c.encode(month, forKey: .month)
            try c.encode(dayOfMonth, forKey: .dayOfMonth)
        }
    }
}

/// 小组件侧本地日历字符串、重复规则文案、到期判断等工具。
enum WGCalendar {
    static func localYmd(_ d: Date, calendar: Calendar = .current) -> String {
        let y = calendar.component(.year, from: d)
        let m = calendar.component(.month, from: d)
        let day = calendar.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, m, day)
    }

    /// 解析 `YYYY-MM-DD`；若字符串为 ISO8601 日期时间（含 `T`），只取日期段，避免第三段变成 `15T00…` 导致解析失败。
    static func parseLocalYmd(_ s: String, calendar: Calendar = .current) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let dayPart: String
        if let t = trimmed.firstIndex(of: "T") {
            dayPart = String(trimmed[..<t])
        } else if trimmed.count >= 10 {
            dayPart = String(trimmed.prefix(10))
        } else {
            dayPart = trimmed
        }
        let p = dayPart.split(separator: "-").compactMap { Int($0) }
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

    static func isYearlyDue(month: Int, dayOfMonth: Int, ref: Date, calendar: Calendar = .current) -> Bool {
        guard (1 ... 12).contains(month) else { return false }
        let refMonth = calendar.component(.month, from: ref)
        guard refMonth == month else { return false }
        let y = calendar.component(.year, from: ref)
        let mIdx = month - 1
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

    static func excludesWeekendDueDate(skipWeekends: Bool, ref: Date, calendar: Calendar = .current) -> Bool {
        skipWeekends && calendar.isDateInWeekend(ref)
    }

    static func isTaskDueOn(recurrence: WGRecurrence, ref: Date, calendar: Calendar = .current) -> Bool {
        switch recurrence {
        case let .daily(skipWeekends):
            if excludesWeekendDueDate(skipWeekends: skipWeekends, ref: ref, calendar: calendar) { return false }
            return true
        case let .everyNDays(intervalDays, anchor):
            return isDueEveryNDays(intervalDays: intervalDays, anchorYmd: anchor, ref: ref, calendar: calendar)
        case let .weekly(weekdayJs, skipWeekends):
            // 与主应用 `LocalCalendarDate.appleWeekday(fromJSWeekday:)` 一致：JS 一周 0…6，规范化后再 +1 对齐 `Calendar.Component.weekday`（1=周日…）。
            let js = ((weekdayJs % 7) + 7) % 7
            guard calendar.component(.weekday, from: ref) == js + 1 else { return false }
            if excludesWeekendDueDate(skipWeekends: skipWeekends, ref: ref, calendar: calendar) { return false }
            return true
        case let .monthly(dayOfMonth):
            return isMonthlyDueDay(dayOfMonth: dayOfMonth, ref: ref, calendar: calendar)
        case let .yearly(month, dayOfMonth):
            return isYearlyDue(month: month, dayOfMonth: dayOfMonth, ref: ref, calendar: calendar)
        }
    }

    static func recurrenceLabel(_ r: WGRecurrence) -> String {
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        switch r {
        case let .daily(skipWeekends):
            return skipWeekends ? "每个工作日" : "每天"
        case let .everyNDays(interval, _):
            return interval <= 1 ? "每天" : "每 \(interval) 天"
        case let .weekly(weekdayJs, skipWeekends):
            let idx = ((weekdayJs % 7) + 7) % 7
            var base = "每周\(weekdays[idx])"
            if skipWeekends, idx == 0 || idx == 6 {
                base += "（周末除外）"
            }
            return base
        case let .monthly(day):
            return "每月 \(day) 日"
        case let .yearly(month, day):
            return "每年 \(month) 月 \(day) 日"
        }
    }
}

/// 与主应用一次性提醒 JSON 一致的解码模型。
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

    /// 小组件「今日待办」一次性提醒：列表仅含今日，副标题只展示时分。
    func fireSummaryTimeTodayRow() -> String {
        String(format: "%02d:%02d", hour, minute)
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

/// 与主应用循环任务 JSON 一致的解码模型（含 `showInWidget`）。
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
    var showInWidget: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, recurrence, notifyEnabled, notifyHour, notifyMinute, notificationIds, createdAt, completedYmds, showInWidget
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        recurrence = try c.decode(WGRecurrence.self, forKey: .recurrence)
        notifyEnabled = try c.decodeIfPresent(Bool.self, forKey: .notifyEnabled) ?? false
        notifyHour = try c.decodeIfPresent(Int.self, forKey: .notifyHour) ?? 9
        notifyMinute = try c.decodeIfPresent(Int.self, forKey: .notifyMinute) ?? 0
        notificationIds = try c.decodeIfPresent([String].self, forKey: .notificationIds) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? WGCalendar.localYmd(Date())
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
}

// MARK: - 时段任务（与主应用 `hourly_window_tasks.json` 一致）

/// 与主应用时段任务 JSON 一致的解码模型。
struct WGHourlyWindowTask: Codable, Identifiable {
    var id: String
    var title: String
    /// 与主应用一致：分钟 1…1440；JSON 可读旧字段 `intervalHours`（×60）。
    var intervalMinutes: Int
    var windowStartHour: Int
    var windowStartMinute: Int
    var windowEndHour: Int
    var windowEndMinute: Int
    /// 0 = 结束在同一天；1 = 结束在次日（与主应用、日期选择器一致）。
    var windowEndDayOffset: Int
    var weekdaysOnly: Bool
    var notifyEnabled: Bool
    var notificationIds: [String]
    var createdAt: String
    var completedYmds: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, intervalMinutes, intervalHours
        case windowStartHour, windowStartMinute, windowEndHour, windowEndMinute
        case windowEndDayOffset
        case weekdaysOnly, notifyEnabled, notificationIds, createdAt, completedYmds
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
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? WGCalendar.localYmd(Date())
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

    func isActive(on dayDate: Date, calendar: Calendar) -> Bool {
        HourlyWindowScheduling.appliesToDay(weekdaysOnly: weekdaysOnly, date: dayDate, calendar: calendar)
    }
}

// MARK: - 需求清单（与主应用 `project_checklists.json` 一致，字段从简解码）

/// 子任务行：仅解参与进度、完成态相关的键，其余 JSON 字段忽略。
struct WGProjectChecklistSubItem: Decodable, Identifiable {
    var id: String
    var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, isCompleted
    }

    init(id: String, isCompleted: Bool) {
        self.id = id
        self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = try c.decodeIfPresent(String.self, forKey: .id)
        id = (rawId?.isEmpty == false) ? rawId! : UUID().uuidString
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}

/// 与主应用 `ProjectChecklist` 对齐的需求清单（小组件只读）。
struct WGProjectChecklist: Decodable, Identifiable {
    var id: String
    var title: String
    var startYmd: String?
    var dueYmd: String?
    var isCompleted: Bool
    var items: [WGProjectChecklistSubItem]

    enum CodingKeys: String, CodingKey {
        case id, title, startYmd, dueYmd, isCompleted, items
    }

    init(id: String, title: String, startYmd: String?, dueYmd: String?, isCompleted: Bool, items: [WGProjectChecklistSubItem]) {
        self.id = id
        self.title = title
        self.startYmd = startYmd
        self.dueYmd = dueYmd
        self.isCompleted = isCompleted
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startYmd = try c.decodeIfPresent(String.self, forKey: .startYmd)
        dueYmd = try c.decodeIfPresent(String.self, forKey: .dueYmd)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        /// 子项数组异常或缺失时降级为空，避免整份需求清单无法解码。
        items = (try? c.decodeIfPresent([WGProjectChecklistSubItem].self, forKey: .items)) ?? []
    }

    /// 整文件 `JSONDecoder` 失败时，从字典逐条容错解析（避免子项结构差异导致小组件读不到清单）。
    init?(lossyDict obj: [String: Any]) {
        guard let id = obj["id"] as? String, !id.isEmpty else { return nil }
        let title = obj["title"] as? String ?? ""
        let startYmd = Self.ymdStringFromLossyJSON(obj["startYmd"])
        let dueYmd = Self.ymdStringFromLossyJSON(obj["dueYmd"])
        let isCompleted = obj["isCompleted"] as? Bool ?? false
        let items = Self.parseItemsLossy(obj["items"])
        self.init(id: id, title: title, startYmd: startYmd, dueYmd: dueYmd, isCompleted: isCompleted, items: items)
    }

    /// lossy 解码时 `startYmd`/`dueYmd` 可能是字符串或其它 JSON 标量（历史数据、手改文件）。
    private static func ymdStringFromLossyJSON(_ any: Any?) -> String? {
        switch any {
        case nil:
            return nil
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            let t = n.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        default:
            return nil
        }
    }

    private static func parseItemsLossy(_ any: Any?) -> [WGProjectChecklistSubItem] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            let id = (d["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
            let done = d["isCompleted"] as? Bool ?? false
            return WGProjectChecklistSubItem(id: id, isCompleted: done)
        }
    }

    static func lossyArray(from data: Data) -> [WGProjectChecklist]? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let parsed = arr.compactMap { WGProjectChecklist(lossyDict: $0) }
        return parsed.isEmpty ? nil : parsed
    }

    /// 与主应用 `ProjectChecklist.showsOnCalendar(on:calendar:)` 一致。
    /// 使用「日历日」比较，避免 `yyyy-M-d` 与 `yyyy-MM-dd` 混用时 **字符串** 比较出错。
    func showsOnCalendar(on ymd: String, calendar: Calendar = .current) -> Bool {
        guard let yDay = WGCalendar.parseLocalYmd(ymd, calendar: calendar) else { return false }
        let y0 = calendar.startOfDay(for: yDay)
        switch (startYmd, dueYmd) {
        case (nil, nil):
            return false
        case let (s?, nil):
            guard let dS = WGCalendar.parseLocalYmd(s, calendar: calendar) else { return false }
            return calendar.isDate(y0, inSameDayAs: dS)
        case let (nil, d?):
            guard let dD = WGCalendar.parseLocalYmd(d, calendar: calendar) else { return false }
            return calendar.isDate(y0, inSameDayAs: dD)
        case let (s?, d?):
            guard let dS = WGCalendar.parseLocalYmd(s, calendar: calendar),
                  let dE = WGCalendar.parseLocalYmd(d, calendar: calendar)
            else { return false }
            var s0 = calendar.startOfDay(for: dS)
            var e0 = calendar.startOfDay(for: dE)
            if s0 > e0 { swap(&s0, &e0) }
            return y0 >= s0 && y0 <= e0
        }
    }

    private var completedSubItemCount: Int { items.filter(\.isCompleted).count }
    private var totalSubItemCount: Int { items.count }

    private func subtaskProgressLine() -> String {
        if totalSubItemCount == 0 { return "无子项" }
        return "\(completedSubItemCount)/\(totalSubItemCount) 子项"
    }

    private func calendarDateSummary() -> String {
        switch (startYmd, dueYmd) {
        case (nil, nil):
            return "未设日期"
        case let (s?, nil):
            return "自 \(Self.compactYmd(s)) 起"
        case let (nil, d?):
            return "截止 \(Self.compactYmd(d))"
        case let (s?, d?):
            return "\(Self.compactYmd(s)) – \(Self.compactYmd(d))"
        }
    }

    /// 与主应用 `calendarDetailLine()` 一致，用于副标题。
    func calendarDetailLine() -> String {
        let progress = subtaskProgressLine()
        let dates = calendarDateSummary()
        if dates == "未设日期" {
            return progress
        }
        return "\(progress) · \(dates)"
    }

    private static func compactYmd(_ ymd: String) -> String {
        let p = ymd.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return ymd }
        return "\(p[1])/\(p[2])"
    }

    /// 在清单仍覆盖的日期内，取 **不早于** `todayYmd` 的最早一日；与月历「某日是否出现」一致。
    /// 使用 `Date` 比较，避免仅「开始日」在未来时因字符串序错误而判成「无下一日」。
    func earliestCalendarYmd(onOrAfter todayYmd: String, calendar: Calendar = .current) -> String? {
        guard let tDay = WGCalendar.parseLocalYmd(todayYmd, calendar: calendar) else { return nil }
        let t0 = calendar.startOfDay(for: tDay)
        switch (startYmd, dueYmd) {
        case (nil, nil):
            return nil
        case let (s?, nil), let (nil, s?):
            guard let dS = WGCalendar.parseLocalYmd(s, calendar: calendar) else { return nil }
            let s0 = calendar.startOfDay(for: dS)
            if s0 >= t0 { return WGCalendar.localYmd(s0, calendar: calendar) }
            return nil
        case let (s?, d?):
            guard let dS = WGCalendar.parseLocalYmd(s, calendar: calendar),
                  let dE = WGCalendar.parseLocalYmd(d, calendar: calendar)
            else { return nil }
            var s0 = calendar.startOfDay(for: dS)
            var e0 = calendar.startOfDay(for: dE)
            if s0 > e0 { swap(&s0, &e0) }
            let lower = max(s0, t0)
            if lower <= e0 { return WGCalendar.localYmd(lower, calendar: calendar) }
            return nil
        }
    }
}

// MARK: - IO

/// App Group 下读写与主应用相同的 JSON 数组（读优先非空文件；扩展侧少量写回用于调试或将来能力）。
enum TodayWidgetIO {
    private static var didLogMissingGroupContainer = false
    private static let decoder = JSONDecoder()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// 与主应用 `LocalJSONStore` 使用同一 App Group；极少数环境下 `containerURL` 对扩展返回 nil，再尝试固定路径。
    private static func appGroupContainerRoot() -> URL? {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetAppGroup.identifier) {
            return u
        }
        #if os(macOS)
        let path = NSHomeDirectory() + "/Library/Group Containers/" + WidgetAppGroup.identifier
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return nil
    }

    /// 仅 **App Group** 下 `MiniToolsData`（与 `LocalJSONStore` 一致）。
    /// 不在此回退到 `Application Support`：扩展进程的 Support 与主应用 **不是同一目录**，读不到主应用写入的 JSON，只会造成「App 里有数据、小组件永远空」的假问题。
    private static func jsonURLs(fileName: String) -> [URL] {
        guard let root = appGroupContainerRoot() else {
            if !didLogMissingGroupContainer {
                didLogMissingGroupContainer = true
                TodayWidgetDebugLog.log.error("App Group 容器不可用，无法读取共享 JSON（例如 \(fileName, privacy: .public)）；请检查扩展的 App Group 能力。")
            }
            return []
        }
        let dir = root.appending(path: MiniToolsDataIsolation.appGroupJSONDirectoryName, directoryHint: .isDirectory)
        return [dir.appending(path: fileName, directoryHint: .notDirectory)]
    }

    /// 对 **数组** JSON：返回首个非空解码结果（单一路径，见 `jsonURLs`）。
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
        guard let root = appGroupContainerRoot() else { return nil }
        let dir = root.appending(path: MiniToolsDataIsolation.appGroupJSONDirectoryName, directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
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

    static func loadHourlyWindow() -> [WGHourlyWindowTask] {
        loadJSONArray([WGHourlyWindowTask].self, fileName: "hourly_window_tasks.json")
    }

    static func loadProjectChecklists() -> [WGProjectChecklist] {
        let groupRoot = appGroupContainerRoot()?.path ?? "(nil)"
        TodayWidgetDebugLog.log.debug("loadProjectChecklists: appGroupRoot=\(groupRoot, privacy: .public)")
        for url in jsonURLs(fileName: "project_checklists.json") {
            let exists = FileManager.default.fileExists(atPath: url.path)
            TodayWidgetDebugLog.log.debug("  try path=\(url.path, privacy: .public) exists=\(exists, privacy: .public)")
            guard exists else { continue }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            if let v = try? decoder.decode([WGProjectChecklist].self, from: data) {
                if !v.isEmpty {
                    TodayWidgetDebugLog.log.debug("  decoded strict count=\(v.count, privacy: .public)")
                    return v
                }
                TodayWidgetDebugLog.log.debug("  strict decode ok but empty [], try next URL")
                continue
            }
            if let lossy = WGProjectChecklist.lossyArray(from: data), !lossy.isEmpty {
                TodayWidgetDebugLog.log.debug("  decoded lossy count=\(lossy.count, privacy: .public)")
                return lossy
            }
            TodayWidgetDebugLog.log.debug("  decode failed (strict+lossy) for this file")
        }
        TodayWidgetDebugLog.log.debug("loadProjectChecklists: returning empty")
        return []
    }

    static func saveRecurring(_ items: [WGRecurringTask]) throws {
        guard let dir = dataDirectory else { throw CocoaError(.fileNoSuchFile) }
        let url = dir.appending(path: "recurring_tasks.json", directoryHint: .notDirectory)
        let data = try encoder.encode(items)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - 今日行（小组件用）

/// 「今日待办」列表中的一行展示数据（定时 / 例行 / 需求清单 / 时段），用于 SwiftUI 与 `WidgetDeepLink`。
struct TodayRowData: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let isOneTime: Bool
    /// `true` 时表示时段任务，`isOneTime` 为 `false`。
    let isHourly: Bool
    /// `true` 时表示需求清单；与 `isOneTime`、`isHourly` 互斥。
    let isProjectChecklist: Bool
    let rawId: String
    let todayYmd: String
    /// 仅一次性提醒有值；列表副标题只认此处 + `isOneTime`，不依赖 `subtitle` 字符串（避免时间线缓存里夹带旧版「日期+时间」文案）。
    let oneTimeHour: Int?
    let oneTimeMinute: Int?

    /// 今日待办列表展示：小/中/大共用，不按 `widgetFamily` 分支。
    var todayListDisplaySubtitle: String {
        if isOneTime, let h = oneTimeHour, let m = oneTimeMinute {
            return String(format: "定时 · %02d:%02d", h, m)
        }
        return subtitle
    }
}

/// 小组件「下一次」区块所用的预告信息（主应用逻辑对齐：按时间取最早一条）。
struct NextUpTaskInfo {
    let title: String
    let detail: String
    let isOneTime: Bool
    let isHourly: Bool
    /// `true` 表示需求清单（与例行区分：两者 `isOneTime`/`isHourly` 均为 `false`）。
    let isProjectChecklist: Bool
    let rawId: String
    /// 例行任务勾选链接必填；一次性可填 `dateYmd` 备用。
    let ymdForRecurring: String
}

/// 从磁盘 JSON 组装今日行与「下次待办」，与主应用日历逻辑对齐（日历、去重、迟到创建日过滤等）。
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
    /// `nextUpChecklist`：当主条被定时/例行/时段等占满时，单独预告「即将的需求清单」，避免被每日例行永远压在后面。
    static func loadEntry(at now: Date) -> (rows: [TodayRowData], nextUp: NextUpTaskInfo?, nextUpChecklist: NextUpTaskInfo?) {
        let cal = widgetCalendar
        let oneTimes = TodayWidgetIO.loadOneTimes()
        let recurring = TodayWidgetIO.loadRecurring()
        let hourly = TodayWidgetIO.loadHourlyWindow()
        let checklists = TodayWidgetIO.loadProjectChecklists()
        let rows = makeRows(
            now: now,
            calendar: cal,
            oneTimes: oneTimes,
            recurring: recurring,
            hourly: hourly,
            checklists: checklists
        )
        var skipOneTimeIds: Set<String> = []
        var skipRecurringDayKeys: Set<String> = []
        var skipHourlyDayKeys: Set<String> = []
        var skipChecklistIds: Set<String> = []
        for row in rows {
            if row.isOneTime {
                skipOneTimeIds.insert(row.rawId)
            } else if row.isHourly {
                skipHourlyDayKeys.insert("\(row.rawId)|\(row.todayYmd)")
            } else if row.isProjectChecklist {
                skipChecklistIds.insert(row.rawId)
            } else {
                skipRecurringDayKeys.insert("\(row.rawId)|\(row.todayYmd)")
            }
        }
        let (next, nextChecklist) = computeNextUpcoming(
            now: now,
            calendar: cal,
            oneTimes: oneTimes,
            recurring: recurring,
            hourly: hourly,
            checklists: checklists,
            skipOneTimeIds: skipOneTimeIds,
            skipRecurringDayKeys: skipRecurringDayKeys,
            skipHourlyDayKeys: skipHourlyDayKeys,
            skipChecklistIds: skipChecklistIds
        )
        return (rows, next, nextChecklist)
    }

    static func loadRows(now: Date, calendar cal: Calendar) -> [TodayRowData] {
        makeRows(
            now: now,
            calendar: cal,
            oneTimes: TodayWidgetIO.loadOneTimes(),
            recurring: TodayWidgetIO.loadRecurring(),
            hourly: TodayWidgetIO.loadHourlyWindow(),
            checklists: TodayWidgetIO.loadProjectChecklists()
        )
    }

    private static func makeRows(
        now: Date,
        calendar cal: Calendar,
        oneTimes: [WGOneTimeReminder],
        recurring: [WGRecurringTask],
        hourly: [WGHourlyWindowTask],
        checklists: [WGProjectChecklist]
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
                subtitle: "定时 · \(o.fireSummaryTimeTodayRow())",
                isOneTime: true,
                isHourly: false,
                isProjectChecklist: false,
                rawId: o.id,
                todayYmd: today,
                oneTimeHour: o.hour,
                oneTimeMinute: o.minute
            ))
        }

        let recs = recurring
            .filter {
                guard $0.showInWidget else { return false }
                guard WGCalendar.isTaskDueOn(recurrence: $0.recurrence, ref: now, calendar: cal) else { return false }
                guard !$0.completedYmds.contains(today) else { return false }
                return !RecurringLateCreationDayFilter.shouldOmitFromDisplay(
                    createdAtYmd: $0.createdAt,
                    notifyEnabled: $0.notifyEnabled,
                    notifyHour: $0.notifyHour,
                    notifyMinute: $0.notifyMinute,
                    cellDayYmd: today,
                    now: now,
                    calendar: cal
                )
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        for t in recs {
            rows.append(TodayRowData(
                id: "r-\(t.id)",
                title: t.title.isEmpty ? "（无标题）" : t.title,
                subtitle: "例行 · \(WGCalendar.recurrenceLabel(t.recurrence))",
                isOneTime: false,
                isHourly: false,
                isProjectChecklist: false,
                rawId: t.id,
                todayYmd: today,
                oneTimeHour: nil,
                oneTimeMinute: nil
            ))
        }

        let pcs = checklists
            .filter { !$0.isCompleted && $0.showsOnCalendar(on: today, calendar: cal) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        for p in pcs {
            rows.append(TodayRowData(
                id: "c-\(p.id)",
                title: p.title.isEmpty ? "（无标题）" : p.title,
                subtitle: "清单 · \(p.calendarDetailLine())",
                isOneTime: false,
                isHourly: false,
                isProjectChecklist: true,
                rawId: p.id,
                todayYmd: today,
                oneTimeHour: nil,
                oneTimeMinute: nil
            ))
        }

        guard let todayDate = WGCalendar.parseLocalYmd(today, calendar: cal) else { return rows }
        let hrs = hourly
            .filter { h in
                guard h.isValidWindow(), h.isActive(on: todayDate, calendar: cal) else { return false }
                return !h.completedYmds.contains(today)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        for h in hrs {
            rows.append(TodayRowData(
                id: "h-\(h.id)",
                title: h.title.isEmpty ? "（无标题）" : h.title,
                subtitle: "时段 · \(h.summaryScheduleLabel())",
                isOneTime: false,
                isHourly: true,
                isProjectChecklist: false,
                rawId: h.id,
                todayYmd: today,
                oneTimeHour: nil,
                oneTimeMinute: nil
            ))
        }

        return rows
    }

    private static let upcomingScanDays = 1200

    /// 未完成的一次性提醒（按触发时刻）或例行任务（下一到期日且该日未勾选）中时间上更早的一条。
    static func loadNextUpcoming(now: Date = Date(), calendar cal: Calendar? = nil) -> (NextUpTaskInfo?, NextUpTaskInfo?) {
        let c = cal ?? widgetCalendar
        return computeNextUpcoming(
            now: now,
            calendar: c,
            oneTimes: TodayWidgetIO.loadOneTimes(),
            recurring: TodayWidgetIO.loadRecurring(),
            hourly: TodayWidgetIO.loadHourlyWindow(),
            checklists: TodayWidgetIO.loadProjectChecklists(),
            skipOneTimeIds: [],
            skipRecurringDayKeys: [],
            skipHourlyDayKeys: [],
            skipChecklistIds: []
        )
    }

    private static func nextUpInfoForChecklist(_ p: WGProjectChecklist, ymd: String) -> NextUpTaskInfo {
        let detail = "\(ymd) (\(p.calendarDetailLine())) (清单)"
        return NextUpTaskInfo(
            title: p.title.isEmpty ? "（无标题）" : p.title,
            detail: detail,
            isOneTime: false,
            isHourly: false,
            isProjectChecklist: true,
            rawId: p.id,
            ymdForRecurring: ymd
        )
    }

    private static func computeNextUpcoming(
        now: Date,
        calendar c: Calendar,
        oneTimes allOne: [WGOneTimeReminder],
        recurring allRec: [WGRecurringTask],
        hourly allHourly: [WGHourlyWindowTask],
        checklists allChecklists: [WGProjectChecklist],
        skipOneTimeIds: Set<String> = [],
        skipRecurringDayKeys: Set<String> = [],
        skipHourlyDayKeys: Set<String> = [],
        skipChecklistIds: Set<String> = []
    ) -> (NextUpTaskInfo?, NextUpTaskInfo?) {
        let startToday = c.startOfDay(for: now)

        let oneTimes = allOne.filter { !$0.isCompleted }
        /// 触发时刻 **不早于** `now` 的定时（用于与其它「未来」候选比较）。
        var bestOneFuture: WGOneTimeReminder?
        var bestOneFireFuture: Date?
        for o in oneTimes {
            guard !skipOneTimeIds.contains(o.id) else { continue }
            guard let fd = o.fireDate(calendar: c) else { continue }
            if fd >= now {
                if bestOneFireFuture == nil || fd < bestOneFireFuture! {
                    bestOneFuture = o
                    bestOneFireFuture = fd
                }
            }
        }
        /// 已过期的一次性提醒（仅当不存在任何「未来」候选时作为「下次」回退，避免压住若干天后的需求清单）。
        var bestOnePast: WGOneTimeReminder?
        var bestOneFirePast: Date?
        for o in oneTimes {
            guard !skipOneTimeIds.contains(o.id) else { continue }
            guard let fd = o.fireDate(calendar: c) else { continue }
            if fd < now {
                if bestOneFirePast == nil || fd < bestOneFirePast! {
                    bestOnePast = o
                    bestOneFirePast = fd
                }
            }
        }

        var bestRecTask: WGRecurringTask?
        var bestRecDate: Date?
        var bestRecYmd: String?

        for t in allRec {
            guard t.showInWidget else { continue }
            guard let hit = firstPendingOccurrence(
                of: t,
                fromStartOfToday: startToday,
                fromNow: now,
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

        var bestHourlyTask: WGHourlyWindowTask?
        var bestHourlyDate: Date?
        var bestHourlyYmd: String?

        for h in allHourly {
            guard let hit = firstPendingHourlySlot(
                task: h,
                from: now,
                calendar: c,
                maxDays: upcomingScanDays,
                skipHourlyDayKeys: skipHourlyDayKeys
            )
            else { continue }
            if bestHourlyDate == nil || hit.sortDate < bestHourlyDate! {
                bestHourlyTask = h
                bestHourlyDate = hit.sortDate
                bestHourlyYmd = hit.ymd
            }
        }

        var bestPc: WGProjectChecklist?
        var bestPcDate: Date?
        var bestPcYmd: String?

        let todayYmd = WGCalendar.localYmd(now, calendar: c)
        for p in allChecklists {
            guard !p.isCompleted else { continue }
            /// 今日已在「今日待办」出现的需求清单不参与「下次待办」（避免与今日重复；区间内其它日也不在此栏预告同一条）。
            guard !skipChecklistIds.contains(p.id) else { continue }
            guard let ymd = p.earliestCalendarYmd(onOrAfter: todayYmd, calendar: c) else { continue }
            guard p.showsOnCalendar(on: ymd, calendar: c) else { continue }
            guard let dayDate = WGCalendar.parseLocalYmd(ymd, calendar: c) else { continue }
            let sortDate = c.startOfDay(for: dayDate)
            if bestPcDate == nil || sortDate < bestPcDate! {
                bestPc = p
                bestPcDate = sortDate
                bestPcYmd = ymd
            } else if let b = bestPcDate, sortDate == b, let cur = bestPc {
                if p.title.localizedCompare(cur.title) == .orderedAscending {
                    bestPc = p
                    bestPcYmd = ymd
                }
            }
        }

        enum Winner { case one, rec, hourly, checklist }
        var winner: Winner?
        var winDate: Date?
        var oneTimeWinnerIsPast = false

        if let o = bestOneFireFuture {
            winner = .one
            winDate = o
        }
        if let r = bestRecDate {
            if winDate == nil || r < winDate! {
                winner = .rec
                winDate = r
            }
        }
        if let h = bestHourlyDate {
            if winDate == nil || h < winDate! {
                winner = .hourly
                winDate = h
            }
        }
        if let pc = bestPcDate {
            if winDate == nil || pc < winDate! {
                winner = .checklist
                winDate = pc
            }
        }
        if winner == nil, let d = bestOneFirePast {
            winner = .one
            winDate = d
            oneTimeWinnerIsPast = true
        }
        TodayWidgetDebugLog.log.debug(
            "computeNextUpcoming: today=\(todayYmd, privacy: .public) checklists=\(allChecklists.count, privacy: .public) skipPc=\(skipChecklistIds.count, privacy: .public) winner=\(String(describing: winner), privacy: .public) bestPcYmd=\(bestPcYmd ?? "nil", privacy: .public)"
        )
        guard winner != nil else { return (nil, nil) }

        // 「下次待办」副标题：`yyyy-MM-dd HH:mm (说明)`，说明里为规则文案（与预览 host 一致）。
        let primary: NextUpTaskInfo?
        switch winner! {
        case .one:
            guard let o = oneTimeWinnerIsPast ? bestOnePast : bestOneFuture else { return (nil, nil) }
            let timeStr = String(format: "%02d:%02d", o.hour, o.minute)
            let detail = "\(o.dateYmd) \(timeStr) (定时)"
            primary = NextUpTaskInfo(
                title: o.title.isEmpty ? "（无标题）" : o.title,
                detail: detail,
                isOneTime: true,
                isHourly: false,
                isProjectChecklist: false,
                rawId: o.id,
                ymdForRecurring: o.dateYmd
            )
        case .rec:
            guard let r = bestRecTask, let ymd = bestRecYmd else { return (nil, nil) }
            let recLabel = WGCalendar.recurrenceLabel(r.recurrence)
            let detail: String
            if r.notifyEnabled {
                let timeStr = String(format: "%02d:%02d", r.notifyHour, r.notifyMinute)
                detail = "\(ymd) \(timeStr) (\(recLabel))"
            } else {
                detail = "\(ymd) (\(recLabel))"
            }
            primary = NextUpTaskInfo(
                title: r.title.isEmpty ? "（无标题）" : r.title,
                detail: detail,
                isOneTime: false,
                isHourly: false,
                isProjectChecklist: false,
                rawId: r.id,
                ymdForRecurring: ymd
            )
        case .hourly:
            guard let h = bestHourlyTask, let ht = bestHourlyDate, let ymd = bestHourlyYmd else { return (nil, nil) }
            let hcomp = c.component(.hour, from: ht)
            let mcomp = c.component(.minute, from: ht)
            let timeStr = String(format: "%02d:%02d", hcomp, mcomp)
            let detail = "\(ymd) \(timeStr) (\(h.summaryScheduleLabel()))"
            primary = NextUpTaskInfo(
                title: h.title.isEmpty ? "（无标题）" : h.title,
                detail: detail,
                isOneTime: false,
                isHourly: true,
                isProjectChecklist: false,
                rawId: h.id,
                ymdForRecurring: ymd
            )
        case .checklist:
            guard let p = bestPc, let ymd = bestPcYmd else { return (nil, nil) }
            primary = nextUpInfoForChecklist(p, ymd: ymd)
        }

        var checklistSecondary: NextUpTaskInfo?
        if winner != .checklist, let p = bestPc, let ymd = bestPcYmd {
            checklistSecondary = nextUpInfoForChecklist(p, ymd: ymd)
        }
        return (primary, checklistSecondary)
    }

    private static func firstPendingHourlySlot(
        task: WGHourlyWindowTask,
        from now: Date,
        calendar cal: Calendar,
        maxDays: Int,
        skipHourlyDayKeys: Set<String>
    ) -> (sortDate: Date, ymd: String)? {
        guard task.isValidWindow() else { return nil }
        let startToday = cal.startOfDay(for: now)
        for offset in 0 ..< maxDays {
            guard let d = cal.date(byAdding: .day, value: offset, to: startToday) else { continue }
            let dayStart = cal.startOfDay(for: d)
            let ymd = WGCalendar.localYmd(dayStart, calendar: cal)
            if task.completedYmds.contains(ymd) { continue }
            if skipHourlyDayKeys.contains("\(task.id)|\(ymd)") { continue }
            let slots = HourlyWindowScheduling.slotDates(on: dayStart, calendar: cal, config: task.hourlyWindowConfig)
            for slot in slots.sorted() where slot > now {
                return (slot, ymd)
            }
        }
        return nil
    }

    private static func firstPendingOccurrence(
        of task: WGRecurringTask,
        fromStartOfToday startToday: Date,
        fromNow now: Date,
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
            if RecurringLateCreationDayFilter.shouldOmitFromDisplay(
                createdAtYmd: task.createdAt,
                notifyEnabled: task.notifyEnabled,
                notifyHour: task.notifyHour,
                notifyMinute: task.notifyMinute,
                cellDayYmd: ymd,
                now: now,
                calendar: cal
            ) {
                continue
            }
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
