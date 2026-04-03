//
//  RecurringLateCreationDayFilter.swift
//  MiniToolsCore
//
//  创建日当天若「到点提醒」时刻已过，则该日不计入待办（首次出现在下一到期日），避免下午新建 9:00 例行仍出现在「今天」。
//

import Foundation

/// 若例行任务创建日下午已过当天提醒点，则当天不在列表/小组件展示（首次出现在下一到期日）。
public enum RecurringLateCreationDayFilter {
    /// - Parameters:
    ///   - createdAtYmd: 任务 `createdAt`（本地日历 `YYYY-MM-DD`）
    ///   - cellDayYmd: 正在展示的日历日
    ///   - now: 当前时刻（与 UI 一致）
    public static func shouldOmitFromDisplay(
        createdAtYmd: String,
        notifyEnabled: Bool,
        notifyHour: Int,
        notifyMinute: Int,
        cellDayYmd: String,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard notifyEnabled else { return false }
        guard createdAtYmd == cellDayYmd else { return false }

        let parts = cellDayYmd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var dc = DateComponents()
        dc.year = parts[0]
        dc.month = parts[1]
        dc.day = parts[2]
        guard let dayDate = calendar.date(from: dc) else { return false }
        let dayStart = calendar.startOfDay(for: dayDate)

        let h = min(23, max(0, notifyHour))
        let mi = min(59, max(0, notifyMinute))
        guard let fire = calendar.date(bySettingHour: h, minute: mi, second: 0, of: dayStart) else { return false }
        return now > fire
    }
}
