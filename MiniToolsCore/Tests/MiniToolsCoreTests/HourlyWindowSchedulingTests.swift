import Foundation
import MiniToolsCore
import Testing

@Suite struct HourlyWindowSchedulingTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    @Test func sameDaySlots() {
        let cfg = HourlyWindowConfig(
            intervalMinutes: 60,
            windowStartHour: 9,
            windowStartMinute: 0,
            windowEndHour: 11,
            windowEndMinute: 0,
            windowEndDayOffset: 0,
            weekdaysOnly: false
        )
        #expect(HourlyWindowScheduling.isValidWindow(cfg, calendar: cal))
        let day = cal.startOfDay(for: DateComponents(calendar: cal, year: 2026, month: 3, day: 31).date!)
        let slots = HourlyWindowScheduling.slotDates(on: day, calendar: cal, config: cfg)
        #expect(slots.count == 3)
        #expect(cal.component(.hour, from: slots[0]) == 9)
        #expect(cal.component(.hour, from: slots[2]) == 11)
    }

    @Test func overnightSlotsNonEmpty() {
        let cfg = HourlyWindowConfig(
            intervalMinutes: 45,
            windowStartHour: 17,
            windowStartMinute: 30,
            windowEndHour: 5,
            windowEndMinute: 30,
            windowEndDayOffset: 1,
            weekdaysOnly: false
        )
        #expect(HourlyWindowScheduling.isValidWindow(cfg, calendar: cal))
        let day1 = cal.startOfDay(for: DateComponents(calendar: cal, year: 2026, month: 3, day: 31).date!)
        let evening = HourlyWindowScheduling.slotDates(on: day1, calendar: cal, config: cfg)
        #expect(!evening.isEmpty)
    }

    @Test func longWindowNextCalendarDay() {
        let cfg = HourlyWindowConfig(
            intervalMinutes: 60,
            windowStartHour: 17,
            windowStartMinute: 30,
            windowEndHour: 17,
            windowEndMinute: 30,
            windowEndDayOffset: 1,
            weekdaysOnly: false
        )
        #expect(HourlyWindowScheduling.isValidWindow(cfg, calendar: cal))
    }

    @Test func scheduleLabelCrossDay() {
        let s = HourlyWindowScheduling.scheduleLabel(
            intervalMinutes: 45,
            startHour: 17,
            startMinute: 30,
            endHour: 5,
            endMinute: 30,
            windowEndDayOffset: 1,
            weekdaysOnly: true
        )
        #expect(s.contains("次日"))
        #expect(s.contains("45"))
    }
}
