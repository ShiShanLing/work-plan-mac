//
//  EfficiencyDateSectionHeader.swift
//  MiniTools-SwiftUI
//

import SwiftUI

enum EfficiencyDateSectionHeader {
    static func title(forYmd ymd: String, calendar: Calendar = .current) -> String {
        guard let d = LocalCalendarDate.parseLocalYmd(ymd, calendar: calendar) else { return ymd }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh-Hans")
        df.dateFormat = "yyyy-MM-dd EEEE"
        return df.string(from: d)
    }

    @MainActor
    @ViewBuilder
    static func label(ymd: String, count: Int, calendar: Calendar = .current) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title(forYmd: ymd, calendar: calendar))
                .font(.headline)
            Text("\(count) 项")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}
