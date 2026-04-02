//
//  ProjectChecklist.swift
//  MiniTools-SwiftUI
//
//  带可选日期区间的需求清单：父级可选开始/截止日（月历区间或单日），子项可逐项勾选完成。
//

import Foundation
import SwiftUI

/// 需求清单侧栏色标（可选；`.none` 表示不标记颜色）。
enum ProjectChecklistTag: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink

    var displayName: String {
        switch self {
        case .none: return "无"
        case .red: return "红"
        case .orange: return "橙"
        case .yellow: return "黄"
        case .green: return "绿"
        case .mint: return "薄荷"
        case .teal: return "青"
        case .blue: return "蓝"
        case .indigo: return "靛"
        case .purple: return "紫"
        case .pink: return "粉"
        }
    }

    /// 侧栏小圆点 / 编辑里用的实心色（`.none` 用占位透明度）。
    var dotFill: Color {
        switch self {
        case .none: return Color.secondary.opacity(0.22)
        case .red: return Color(red: 0.92, green: 0.29, blue: 0.29)
        case .orange: return Color(red: 0.95, green: 0.52, blue: 0.12)
        case .yellow: return Color(red: 0.93, green: 0.76, blue: 0.12)
        case .green: return Color(red: 0.22, green: 0.72, blue: 0.36)
        case .mint: return Color(red: 0.13, green: 0.72, blue: 0.62)
        case .teal: return Color(red: 0.14, green: 0.55, blue: 0.68)
        case .blue: return Color(red: 0.20, green: 0.48, blue: 0.95)
        case .indigo: return Color(red: 0.39, green: 0.37, blue: 0.92)
        case .purple: return Color(red: 0.62, green: 0.36, blue: 0.92)
        case .pink: return Color(red: 0.93, green: 0.34, blue: 0.58)
        }
    }

    /// 月历条 / 当日列表左侧条颜色（未完成更饱和，已完成略淡）。
    func calendarStripeColor(isCompleted: Bool) -> Color {
        guard self != .none else {
            return isCompleted
                ? Color(red: 0.72, green: 0.52, blue: 0.38)
                : Color.orange
        }
        let c = dotFill
        return isCompleted ? c.opacity(0.62) : c
    }
}

/// 子任务优先级（仅影响排序：高 → 低；同级内可拖动调整顺序）。
enum ProjectChecklistSubItemPriority: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case none
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .none: return "无"
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    /// 大者优先（排序用）。
    nonisolated var sortRank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }
}

/// 子任务下的多条细节（可逐项打钩）。
struct ProjectChecklistSubItemDetail: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var isCompleted: Bool
    var completedAtYmd: String?

    init(id: String = UUID().uuidString, title: String, isCompleted: Bool = false, completedAtYmd: String? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAtYmd = completedAtYmd
    }
}

extension Array where Element == ProjectChecklistSubItemDetail {
    /// 未完成细节在前、已完成在后；每组内保持原先相对顺序。
    func withIncompleteDetailsFirst() -> [ProjectChecklistSubItemDetail] {
        filter { !$0.isCompleted } + filter(\.isCompleted)
    }
}

struct ProjectChecklistSubItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var isCompleted: Bool
    var completedAtYmd: String?
    var priority: ProjectChecklistSubItemPriority
    /// 同级（未完成 / 已完成）内的顺序，数值越小越靠上。
    var listOrder: Int
    var details: [ProjectChecklistSubItemDetail]

    enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, completedAtYmd, priority, listOrder, details
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        isCompleted: Bool = false,
        completedAtYmd: String? = nil,
        priority: ProjectChecklistSubItemPriority = .none,
        listOrder: Int = 0,
        details: [ProjectChecklistSubItemDetail] = []
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAtYmd = completedAtYmd
        self.priority = priority
        self.listOrder = listOrder
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAtYmd = try c.decodeIfPresent(String.self, forKey: .completedAtYmd)
        priority = try c.decodeIfPresent(ProjectChecklistSubItemPriority.self, forKey: .priority) ?? .none
        listOrder = try c.decodeIfPresent(Int.self, forKey: .listOrder) ?? 0
        details = try c.decodeIfPresent([ProjectChecklistSubItemDetail].self, forKey: .details) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encodeIfPresent(completedAtYmd, forKey: .completedAtYmd)
        if priority != .none {
            try c.encode(priority, forKey: .priority)
        }
        try c.encode(listOrder, forKey: .listOrder)
        try c.encode(details, forKey: .details)
    }
}

struct ProjectChecklist: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    /// 周期开始（含当日）；与 `dueYmd` 均空则不出现在月历。
    var startYmd: String?
    /// 截止日（含当日）。
    var dueYmd: String?
    var createdAt: String
    /// 整项勾选「已完成」后，月历上仍以已完成样式显示在周期内各日。
    var isCompleted: Bool
    var completedAtYmd: String?
    /// 色标；新建可不选，存为 `.none`。
    var tag: ProjectChecklistTag
    /// 侧栏「进行中 / 已归档」组内顺序；数值越小越靠上。
    var sidebarOrder: Int
    var items: [ProjectChecklistSubItem]

    enum CodingKeys: String, CodingKey {
        case id, title, startYmd, dueYmd, createdAt, isCompleted, completedAtYmd, tag, sidebarOrder, items
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        startYmd: String?,
        dueYmd: String?,
        createdAt: String,
        isCompleted: Bool = false,
        completedAtYmd: String? = nil,
        tag: ProjectChecklistTag = .none,
        sidebarOrder: Int = 0,
        items: [ProjectChecklistSubItem] = []
    ) {
        self.id = id
        self.title = title
        self.startYmd = startYmd
        self.dueYmd = dueYmd
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.completedAtYmd = completedAtYmd
        self.tag = tag
        self.sidebarOrder = sidebarOrder
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        startYmd = try c.decodeIfPresent(String.self, forKey: .startYmd)
        dueYmd = try c.decodeIfPresent(String.self, forKey: .dueYmd)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? LocalCalendarDate.localYmd(Date())
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        completedAtYmd = try c.decodeIfPresent(String.self, forKey: .completedAtYmd)
        tag = try c.decodeIfPresent(ProjectChecklistTag.self, forKey: .tag) ?? .none
        sidebarOrder = try c.decodeIfPresent(Int.self, forKey: .sidebarOrder) ?? 0
        items = try c.decodeIfPresent([ProjectChecklistSubItem].self, forKey: .items) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(startYmd, forKey: .startYmd)
        try c.encodeIfPresent(dueYmd, forKey: .dueYmd)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encodeIfPresent(completedAtYmd, forKey: .completedAtYmd)
        if tag != .none {
            try c.encode(tag, forKey: .tag)
        }
        try c.encode(sidebarOrder, forKey: .sidebarOrder)
        try c.encode(items, forKey: .items)
    }

    /// 列表排序用（子任务）：仅按 `listOrder`，以便 `List.onMove` 拖动时其它行实时腾位；优先级仅作图标/右键标记。
    nonisolated static func sortSubItemsOpen(_ a: ProjectChecklistSubItem, _ b: ProjectChecklistSubItem) -> Bool {
        if a.listOrder != b.listOrder { return a.listOrder < b.listOrder }
        return a.id < b.id
    }

    nonisolated static func sortSubItemsDone(_ a: ProjectChecklistSubItem, _ b: ProjectChecklistSubItem) -> Bool {
        if a.listOrder != b.listOrder { return a.listOrder < b.listOrder }
        return a.id < b.id
    }

    /// 用于月历：`start`+`due` 为闭区间；仅 `start` 或仅 `due` 则只在该日显示。
    func showsOnCalendar(on ymd: String) -> Bool {
        switch (startYmd, dueYmd) {
        case (nil, nil):
            return false
        case let (s?, nil):
            return ymd == s
        case let (nil, d?):
            return ymd == d
        case let (s?, d?):
            return ymd >= s && ymd <= d
        }
    }

    var completedSubItemCount: Int { items.filter(\.isCompleted).count }

    var totalSubItemCount: Int { items.count }

    func calendarDateSummary() -> String {
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

    /// 仅子任务进度，用于列表第二、三行与日历副标题。
    func subtaskProgressLine() -> String {
        if totalSubItemCount == 0 { return "无子项" }
        return "\(completedSubItemCount)/\(totalSubItemCount) 子项"
    }

    /// 侧栏标题行右上：已完成数/总数（无子项时「—」）。
    func subtaskFractionBadge() -> String {
        if totalSubItemCount == 0 { return "—" }
        return "\(completedSubItemCount)/\(totalSubItemCount)"
    }

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

    static func newDraft() -> ProjectChecklist {
        ProjectChecklist(
            id: UUID().uuidString,
            title: "",
            startYmd: nil,
            dueYmd: nil,
            createdAt: LocalCalendarDate.localYmd(Date()),
            isCompleted: false,
            completedAtYmd: nil,
            tag: .none,
            sidebarOrder: 0,
            items: []
        )
    }

    /// 定时提醒预填日期：优先截止日，否则开始日，否则今日。
    func preferredReminderDateYmd(calendar: Calendar = .current) -> String {
        if let d = dueYmd { return d }
        if let s = startYmd { return s }
        return LocalCalendarDate.localYmd(Date(), calendar: calendar)
    }

    /// 保存前规范化：若起止均填且顺序反了则对调。
    mutating func normalizeDateOrder() {
        guard let s = startYmd, let e = dueYmd, s > e else { return }
        startYmd = e
        dueYmd = s
    }
}
