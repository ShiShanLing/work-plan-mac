//
//  RecurringLateCreationDayFilterTests.swift
//

import Foundation
import MiniToolsCore
import Testing

@Suite struct RecurringLateCreationDayFilterTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    @Test func omitsWhenCreatedSameDayAfterNotifyTime() throws {
        // 2026-04-01 14:30 local
        var dc = DateComponents()
        dc.calendar = cal
        dc.timeZone = cal.timeZone
        dc.year = 2026
        dc.month = 4
        dc.day = 1
        dc.hour = 14
        dc.minute = 30
        let now = try #require(cal.date(from: dc))

        let omit = RecurringLateCreationDayFilter.shouldOmitFromDisplay(
            createdAtYmd: "2026-04-01",
            notifyEnabled: true,
            notifyHour: 9,
            notifyMinute: 0,
            cellDayYmd: "2026-04-01",
            now: now,
            calendar: cal
        )
        #expect(omit == true)
    }

    @Test func showsWhenCreatedSameDayBeforeNotifyTime() throws {
        var dc = DateComponents()
        dc.calendar = cal
        dc.timeZone = cal.timeZone
        dc.year = 2026
        dc.month = 4
        dc.day = 1
        dc.hour = 8
        dc.minute = 0
        let now = try #require(cal.date(from: dc))

        let omit = RecurringLateCreationDayFilter.shouldOmitFromDisplay(
            createdAtYmd: "2026-04-01",
            notifyEnabled: true,
            notifyHour: 9,
            notifyMinute: 0,
            cellDayYmd: "2026-04-01",
            now: now,
            calendar: cal
        )
        #expect(omit == false)
    }

    @Test func doesNotOmitNextDayEvenIfCreatedYesterday() throws {
        var dc = DateComponents()
        dc.calendar = cal
        dc.timeZone = cal.timeZone
        dc.year = 2026
        dc.month = 4
        dc.day = 2
        dc.hour = 8
        dc.minute = 0
        let now = try #require(cal.date(from: dc))

        let omit = RecurringLateCreationDayFilter.shouldOmitFromDisplay(
            createdAtYmd: "2026-04-01",
            notifyEnabled: true,
            notifyHour: 9,
            notifyMinute: 0,
            cellDayYmd: "2026-04-02",
            now: now,
            calendar: cal
        )
        #expect(omit == false)
    }
}
