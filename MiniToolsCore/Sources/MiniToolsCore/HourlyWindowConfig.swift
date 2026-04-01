import Foundation

/// 时段提醒用于排期的字段子集（主应用 `HourlyWindowTask` 与小组件模型共用）。
public struct HourlyWindowConfig: Sendable, Equatable {
    public var intervalMinutes: Int
    public var windowStartHour: Int
    public var windowStartMinute: Int
    public var windowEndHour: Int
    public var windowEndMinute: Int
    public var windowEndDayOffset: Int
    public var weekdaysOnly: Bool

    public init(
        intervalMinutes: Int,
        windowStartHour: Int,
        windowStartMinute: Int,
        windowEndHour: Int,
        windowEndMinute: Int,
        windowEndDayOffset: Int,
        weekdaysOnly: Bool
    ) {
        self.intervalMinutes = intervalMinutes
        self.windowStartHour = windowStartHour
        self.windowStartMinute = windowStartMinute
        self.windowEndHour = windowEndHour
        self.windowEndMinute = windowEndMinute
        self.windowEndDayOffset = windowEndDayOffset
        self.weekdaysOnly = weekdaysOnly
    }
}
