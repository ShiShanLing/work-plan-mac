//
//  ProjectChecklistsView.swift
//  MiniTools-SwiftUI
//
//  滴答清单式布局：左侧多清单列表（色标、可删），右侧当前清单子任务；已完成子任务在下方分栏。
//

import AppKit
import SwiftUI

/// 项目清单 Tab：左侧清单侧栏、右侧子任务与细节；支持拖拽排序与 macOS 拖移手柄。
struct ProjectChecklistsView: View {
    @Environment(EfficiencyStore.self) private var store

    @State private var selectedProjectId: String?
    /// 左侧列表当前悬停行的清单 id，用于浅色行背景。
    @State private var sidebarHoveredProjectId: String?
    @State private var editDraft: ProjectChecklist?
    @State private var pendingDeleteMain: ProjectChecklist?
    @State private var oneTimeReminderDraft: OneTimeReminder?

    /// 左侧顺序：进行中在前，已整项完成的清单在后；组内按 `sidebarOrder`（可拖动），缺省同序时按旧规则。
    private var sidebarActive: [ProjectChecklist] {
        store.projectChecklists
            .filter { !$0.isCompleted }
            .sorted { a, b in
                if a.sidebarOrder != b.sidebarOrder { return a.sidebarOrder < b.sidebarOrder }
                let ad = a.dueYmd ?? "9999-12-31"
                let bd = b.dueYmd ?? "9999-12-31"
                if ad != bd { return ad < bd }
                return a.title.localizedCompare(b.title) == .orderedAscending
            }
    }

    private var sidebarDoneProjects: [ProjectChecklist] {
        store.projectChecklists
            .filter(\.isCompleted)
            .sorted { a, b in
                if a.sidebarOrder != b.sidebarOrder { return a.sidebarOrder < b.sidebarOrder }
                let ad = a.completedAtYmd ?? a.createdAt
                let bd = b.completedAtYmd ?? b.createdAt
                if ad != bd { return ad > bd }
                return a.title.localizedCompare(b.title) == .orderedAscending
            }
    }

    var body: some View {
        // 页内左右分栏：用 HStack，不用 HSplitView/NSSplitView，避免左栏被系统当成窗口根侧栏。
        HStack(alignment: .top, spacing: 0) {
            sidebarColumn
            Divider()
            detailColumn
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $editDraft) { draft in
            let creating = !store.projectChecklists.contains(where: { $0.id == draft.id })
            ProjectChecklistEditSheet(draft: draft, isNew: creating) { saved in
                store.upsertProjectChecklist(saved)
                selectedProjectId = saved.id
            }
        }
        .confirmationDialog(
            "删除清单",
            isPresented: Binding(
                get: { pendingDeleteMain != nil },
                set: { if !$0 { pendingDeleteMain = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let p = pendingDeleteMain {
                    let deleted = p.id
                    store.deleteProjectChecklist(id: p.id)
                    if selectedProjectId == deleted {
                        selectedProjectId = store.projectChecklists.first?.id
                    }
                }
                pendingDeleteMain = nil
            }
            Button("取消", role: .cancel) { pendingDeleteMain = nil }
        } message: {
            if let p = pendingDeleteMain {
                Text("确定删除「\(p.title.isEmpty ? "（无标题）" : p.title)」及其全部子任务？此操作不可撤销。")
            }
        }
        .onAppear {
            ensureSelection()
        }
        .onChange(of: store.projectChecklists.map(\.id).sorted().joined(separator: "\n")) { _, _ in
            ensureSelection()
        }
        .sheet(item: $oneTimeReminderDraft) { draft in
            OneTimeReminderEditSheet(store: store, reminder: draft, isNew: true, lockDateYmd: nil)
        }
    }

    private func ensureSelection() {
        guard let s = selectedProjectId else {
            selectedProjectId = store.projectChecklists.first?.id
            return
        }
        if !store.projectChecklists.contains(where: { $0.id == s }) {
            selectedProjectId = store.projectChecklists.first?.id
        }
    }

    /// 左侧列表不让「点空白」把选中项清空（仍可选中其它行；无效 id 时会回退到首条）。
    private var sidebarListSelection: Binding<String?> {
        Binding(
            get: { selectedProjectId },
            set: { newId in
                if let id = newId {
                    selectedProjectId = id
                    return
                }
                if let cur = selectedProjectId,
                   store.projectChecklists.contains(where: { $0.id == cur }) {
                    return
                }
                selectedProjectId = store.projectChecklists.first?.id
            }
        )
    }

    // MARK: 左侧

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("需求清单")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8) 
                Button {
                    editDraft = ProjectChecklist.newDraft()
                } label: {
                    Label("新建", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)

            Text("左侧多清单（色标可选）；按住左键拖动整行可调顺序（行首为排序把手）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            List(selection: sidebarListSelection) {
                if !sidebarActive.isEmpty {
                    Section {
                        ForEach(sidebarActive) { p in
                            sidebarListRow(p)
                                .tag(Optional(p.id))
                        }
                        .onMove { source, destination in
                            var ids = sidebarActive.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            store.applyChecklistSidebarOrder(completedGroup: false, orderedIds: ids)
                        }
                    } header: {
                        Text("进行中")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if !sidebarDoneProjects.isEmpty {
                    Section {
                        ForEach(sidebarDoneProjects) { p in
                            sidebarListRow(p)
                                .tag(Optional(p.id))
                        }
                        .onMove { source, destination in
                            var ids = sidebarDoneProjects.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            store.applyChecklistSidebarOrder(completedGroup: true, orderedIds: ids)
                        }
                    } header: {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.green.opacity(0.85))
                            Text("已完成")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.green.opacity(0.92))
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 200, maxHeight: .infinity)
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebarRowInnerHPadding: CGFloat { 10 }

    // MARK: 左侧清单行外观（固定约定，改动前请先读）
    //
    // 正确做法（当前）：整行高亮只通过 `listRowBackground(sidebarListRowBackground)` —— 底层整格
    // `controlBackgroundColor`，上层内缩圆角 `selectedContentBackgroundColor` / 悬停浅遮罩。
    //
    // 禁止：① `listRowBackground(Color.clear)` 同时又在行 content 上 `.background` 画同款（会双层，
    // 且透明缝会透出 NSTableView 的直角深色选中）；② 只把圆角画在 content 上而不铺满整格。
    //
    private func sidebarRowInnerHighlightFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return Color(nsColor: .selectedContentBackgroundColor) }
        if isHovered { return Color.primary.opacity(0.06) }
        return Color.clear
    }

    /// 仅用于 `listRowBackground`；勿改到行 content 的 `.background`（见上方 MARK 约定）。
    private func sidebarListRowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        let insetH: CGFloat = 10
        let insetV: CGFloat = 2
        return ZStack {
            Color(nsColor: .controlBackgroundColor)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(sidebarRowInnerHighlightFill(isSelected: isSelected, isHovered: isHovered))
                .padding(.horizontal, insetH)
                .padding(.vertical, insetV)
        }
    }

    private func sidebarListRow(_ p: ProjectChecklist) -> some View {
        let isSelected = selectedProjectId == p.id
        let isHovered = sidebarHoveredProjectId == p.id
        // 选中交给 List(selection:) + .tag；行上不要用 Button / onTapGesture（会干扰 onMove）。
        // 行高亮只放在末尾的 `listRowBackground`，勿在此 HStack 上叠加背景（见 MARK「左侧清单行外观」）。
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .center)
                .padding(.top, 3)
                .accessibilityLabel("排序：可按住拖动整行")
            sidebarRowContent(p)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, sidebarRowInnerHPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("单击选中；按住左键拖动整行调整顺序。")
        .onHover { hovering in
            if hovering {
                sidebarHoveredProjectId = p.id
            } else if sidebarHoveredProjectId == p.id {
                sidebarHoveredProjectId = nil
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
        .listRowBackground(sidebarListRowBackground(isSelected: isSelected, isHovered: isHovered))
        .contextMenu {
            Button("添加定时提醒…") {
                oneTimeReminderDraft = OneTimeReminder.draftFromChecklistHint(
                    checklistTitle: p.title,
                    subtaskTitle: nil,
                    dateYmd: p.preferredReminderDateYmd()
                )
            }
            Button("编辑清单…") {
                editDraft = p
            }
            Divider()
            Button("删除清单", role: .destructive) {
                pendingDeleteMain = p
            }
        }
    }

    private func sidebarRowContent(_ p: ProjectChecklist) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                checklistTagDot(tag: p.tag)
                Text(p.title.isEmpty ? "（无标题）" : p.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(p.subtaskFractionBadge())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(p.calendarDateSummary())
                .font(.callout)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func checklistTagDot(tag: ProjectChecklistTag) -> some View {
        Circle()
            .fill(tag == .none ? Color.clear : tag.dotFill)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .strokeBorder(Color.secondary.opacity(tag == .none ? 0.38 : 0.25), lineWidth: tag == .none ? 1 : 0)
            )
            .accessibilityLabel(tag == .none ? "无色标" : "色标：\(tag.displayName)")
    }

    // MARK: 右侧

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selectedProjectId, let p = store.projectChecklists.first(where: { $0.id == id }) {
            ProjectChecklistRightPanel(
                project: p,
                onEditProject: { editDraft = $0 },
                onRequestDeleteProject: { pendingDeleteMain = $0 },
                onComposeOneTimeReminder: { oneTimeReminderDraft = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "选择一个清单",
                systemImage: "sidebar.left",
                description: Text("在左侧新建或点选清单；无清单时请先点「新建」。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 24)
        }
    }
}

// MARK: 右栏：子任务（未完成 / 已完成）

/// 子任务整张卡片尺寸，用于拖移快照与 `SubItemDragCardRasterBody` / `SubItemDragHandleMac` 热点对齐。
private struct SubItemCardSizeKey: PreferenceKey {
    static var defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, n in n })
    }
}

/// 子任务拖影栅格化专用：仅渲染卡片本身（不含 leadPad），输出固定 `cardW × cardH` 的位图。
private struct SubItemDragCardRasterBody: View {
    let sub: ProjectChecklistSubItem
    let cardW: CGFloat
    let cardH: CGFloat
    let completedLook: Bool
    let prioritySymbolName: String?

    private var detailPreviewCap: Int { 6 }

    var body: some View {
        let done = sub.isCompleted
        let pr = sub.priority
        let rawTitle = sub.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailSlice = Array(sub.details.prefix(detailPreviewCap))
        let detailExtra = sub.details.count - detailSlice.count

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 32, alignment: .center)
                if pr != .none, let sym = prioritySymbolName {
                    Image(systemName: sym)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(completedLook ? Color.secondary : Color.accentColor)
                        .frame(width: 16, alignment: .center)
                }
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                Text(rawTitle.isEmpty ? "（无标题）" : sub.title)
                    .font(.callout.weight(completedLook ? .regular : .medium))
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.28))
            )

            if !detailSlice.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(detailSlice) { d in
                        let dDone = d.isCompleted
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 12, alignment: .center)
                            Image(systemName: dDone ? "checkmark.square.fill" : "square")
                                .font(.caption)
                                .foregroundStyle(dDone ? Color.secondary : Color.primary)
                            Text(d.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "（无细节标题）" : d.title)
                                .font(.caption)
                                .foregroundStyle(dDone ? Color.secondary : Color.primary)
                                .lineLimit(1)
                        }
                    }
                    if detailExtra > 0 {
                        Text("还有 \(detailExtra) 条细节…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 4)
                .padding(.top, 1)
            }

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 12, alignment: .center)
                Text("添加任务细节…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
        }
        .padding(8)
        .frame(width: cardW, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    completedLook
                        ? Color(nsColor: .quaternaryLabelColor).opacity(0.14)
                        : Color.accentColor.opacity(0.10)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    completedLook
                        ? Color.secondary.opacity(0.22)
                        : Color.accentColor.opacity(0.42),
                    lineWidth: completedLook ? 1 : 1.25
                )
        )
    }
}

/// 细节行拖影栅格化：简洁水平布局（手柄 + 勾选 + 标题），与实际行内图标/文字水平对齐。
private struct DetailDragCardRasterBody: View {
    let title: String
    let detailDone: Bool
    let rowW: CGFloat

    var body: some View {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 26, alignment: .center)
            Image(systemName: detailDone ? "checkmark.square.fill" : "square")
                .font(.caption)
                .foregroundStyle(detailDone ? Color.secondary : Color.primary)
            Text(t.isEmpty ? "（无细节标题）" : title)
                .font(.caption)
                .foregroundStyle(detailDone ? Color.secondary : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(width: rowW, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        )
    }
}

private struct ProjectChecklistRightPanel: View {
    @Environment(EfficiencyStore.self) private var store

    let project: ProjectChecklist
    var onEditProject: (ProjectChecklist) -> Void
    var onRequestDeleteProject: (ProjectChecklist) -> Void
    var onComposeOneTimeReminder: (OneTimeReminder) -> Void

    @State private var newSubItemTitle = ""
    /// 各子任务「添加细节」输入框草稿，key 为子任务 id。
    @State private var newDetailTextBySubItemId: [String: String] = [:]
    @State private var hoveredSubItemId: String?
    @State private var hoveredDetailKey: String?
    @State private var subItemCardSizeById: [String: CGSize] = [:]
    /// 子任务拖影尺寸在拖动会话内固定，避免 List/悬停态把 `SubItemCardSizeKey` 刷成窄行宽后预览被缩小。
    @State private var subItemDragFrozenCardSize: CGSize?
    /// 子任务拖影位图（`ImageRenderer`）；系统对拖移视图改 proposed size 时不再影响像素尺寸。
    @State private var subItemDragPreviewBitmap: NSImage?
    @State private var subItemDragPreviewBitmapItemId: String?
    /// 滴答清单式：未松手时根据悬停行实时腾位；由拖移预览 `onAppear` 写入。
    @State private var subItemLiveDragId: String?
    @State private var subItemLiveDragIncompleteSection: Bool?
    @State private var subItemLiveReorderTargetBeforeId: String?
    @State private var subItemLiveReorderTargetAtEnd = false
    /// 细节拖移时 `"\(subItemId)|\(detailId)"`，用于原行虚线槽（不依赖拖影 onAppear）。
    @State private var detailLiveDragKey: String?
    @State private var detailDragPreviewBitmap: NSImage?
    @State private var detailDragPreviewBitmapKey: String?
    /// 子任务「细节 + 添加区」是否展开；无记录时：进行中默认展开，已完成默认折叠。
    @State private var subItemDetailsExpanded: [String: Bool] = [:]
    /// 勾选「未完成」子任务为完成时，二次确认；确认后一并勾选所有细节。
    @State private var subItemCompleteConfirmationSubItemId: String?

    private var live: ProjectChecklist? {
        store.projectChecklists.first { $0.id == project.id }
    }

    private func subItemFromLive(_ id: String) -> ProjectChecklistSubItem? {
        live?.items.first { $0.id == id }
    }

    private var openItems: [ProjectChecklistSubItem] {
        (live?.items ?? []).filter { !$0.isCompleted }.sorted(by: ProjectChecklist.sortSubItemsOpen)
    }

    private var doneItems: [ProjectChecklistSubItem] {
        (live?.items ?? []).filter(\.isCompleted).sorted(by: ProjectChecklist.sortSubItemsDone)
    }

    /// 右栏「进行中 / 已完成」与顶区 `headerBlock` 左右对齐（旧版行 inset 为 8）。
    private let subtaskSectionHorizontalInset: CGFloat = 20

    var body: some View {
        List {
            Section {
                headerBlock
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 8, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                HStack(spacing: 10) {
                    TextField("添加子任务，回车或点添加", text: $newSubItemTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addSubItem() }
                    Button("添加") { addSubItem() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newSubItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                if openItems.isEmpty {
                    Text("暂无未完成子任务")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .listRowInsets(EdgeInsets(top: 6, leading: subtaskSectionHorizontalInset, bottom: 6, trailing: subtaskSectionHorizontalInset))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(openItems) { item in
                        subItemRow(item: item, completedLook: false)
                            .listRowInsets(EdgeInsets(top: 4, leading: subtaskSectionHorizontalInset, bottom: 4, trailing: subtaskSectionHorizontalInset))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    if !openItems.isEmpty {
                        subItemDropAtEndOfSection(incompleteSection: true)
                            .listRowInsets(EdgeInsets(top: 0, leading: subtaskSectionHorizontalInset, bottom: 3, trailing: subtaskSectionHorizontalInset))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text("进行中")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, max(0, subtaskSectionHorizontalInset - 8))
                    .padding(.trailing, subtaskSectionHorizontalInset)
            }

            Section {
                if doneItems.isEmpty {
                    Text("完成子任务后会移到这里")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .listRowInsets(EdgeInsets(top: 6, leading: subtaskSectionHorizontalInset, bottom: 6, trailing: subtaskSectionHorizontalInset))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(doneItems) { item in
                        subItemRow(item: item, completedLook: true)
                            .listRowInsets(EdgeInsets(top: 4, leading: subtaskSectionHorizontalInset, bottom: 4, trailing: subtaskSectionHorizontalInset))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    if !doneItems.isEmpty {
                        subItemDropAtEndOfSection(incompleteSection: false)
                            .listRowInsets(EdgeInsets(top: 0, leading: subtaskSectionHorizontalInset, bottom: 3, trailing: subtaskSectionHorizontalInset))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text("已完成")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, max(0, subtaskSectionHorizontalInset - 8))
                    .padding(.trailing, subtaskSectionHorizontalInset)
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("未设开始/截止日的清单不会出现在「日历」月历中。")
                    Text("需求清单仅保存在本机，不会向系统登记通知；若要定时提醒请使用「定时提醒」等页。")
                    Text("按住子任务卡片行首的排序图标拖动，可调整顺序（仅图标可拖，避免影响标题输入框）。细节行首三横线可排序，或拖到另一子任务的细节区（含「添加任务细节」一行附近以接在末尾）。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onPreferenceChange(SubItemCardSizeKey.self) { subItemCardSizeById = $0 }
        .alert("确认将该子任务全部完成？", isPresented: Binding(
            get: { subItemCompleteConfirmationSubItemId != nil },
            set: { if !$0 { subItemCompleteConfirmationSubItemId = nil } }
        )) {
            Button("取消", role: .cancel) {
                subItemCompleteConfirmationSubItemId = nil
            }
            Button("确认") {
                if let sid = subItemCompleteConfirmationSubItemId {
                    store.completeProjectChecklistSubItemAndAllDetails(projectId: project.id, subItemId: sid)
                    subItemDetailsExpanded[sid] = false
                }
                subItemCompleteConfirmationSubItemId = nil
            }
        } message: {
            Text("将把该子任务及其下所有尚未完成的细节一并标记为已完成。")
        }
        .onChange(of: project.id) { _, _ in
            subItemCompleteConfirmationSubItemId = nil
            clearSubItemLiveDragTracking()
        }
        .onDisappear {
            clearSubItemLiveDragTracking()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                let t = live?.tag ?? project.tag
                Circle()
                    .fill(t == .none ? Color.clear : t.dotFill)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.secondary.opacity(t == .none ? 0.35 : 0.2), lineWidth: t == .none ? 1 : 0)
                    )
                    .accessibilityLabel(t == .none ? "无色标" : "色标：\(t.displayName)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.calendarDateSummary())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(project.subtaskProgressLine())
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(project.title.isEmpty ? "（无标题）" : project.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Button {
                    if let p = live { onEditProject(p) }
                } label: {
                    Label("编辑清单", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    if let p = live { onRequestDeleteProject(p) }
                } label: {
                    Label("删除清单", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            if let p = live {
                Toggle(isOn: Binding(
                    get: { p.isCompleted },
                    set: { store.setProjectChecklistCompleted(id: p.id, completed: $0) }
                )) {
                    Text("整项清单标记为已完成（将出现在左侧「已完成」分组）")
                        .font(.subheadline)
                }
                .toggleStyle(.checkbox)
            }
        }
        .contextMenu {
            if let p = live {
                Button("添加定时提醒…") {
                    onComposeOneTimeReminder(
                        OneTimeReminder.draftFromChecklistHint(
                            checklistTitle: p.title,
                            subtaskTitle: nil,
                            dateYmd: p.preferredReminderDateYmd()
                        )
                    )
                }
            }
        }
    }

    private func addSubItem() {
        guard var p = live else { return }
        let t = newSubItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let nextOrder = (p.items.filter { !$0.isCompleted }.map(\.listOrder).max() ?? -1) + 1
        p.items.append(ProjectChecklistSubItem(title: t, listOrder: nextOrder))
        store.upsertProjectChecklist(p)
        newSubItemTitle = ""
    }

    private func deleteSubItem(id: String) {
        guard var p = store.projectChecklists.first(where: { $0.id == project.id }) else { return }
        p.items.removeAll { $0.id == id }
        store.upsertProjectChecklist(p)
        newDetailTextBySubItemId[id] = nil
        subItemDetailsExpanded[id] = nil
    }

    private func subItemDetailsSectionExpanded(subItemId: String, completedLook: Bool) -> Bool {
        subItemDetailsExpanded[subItemId] ?? !completedLook
    }

    private func toggleSubItemDetailsExpansion(subItemId: String, completedLook: Bool) {
        let next = !subItemDetailsSectionExpanded(subItemId: subItemId, completedLook: completedLook)
        subItemDetailsExpanded[subItemId] = next
    }

    private func addDetail(subItemId: String) {
        guard var p = store.projectChecklists.first(where: { $0.id == project.id }),
              let i = p.items.firstIndex(where: { $0.id == subItemId })
        else { return }
        let raw = (newDetailTextBySubItemId[subItemId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        p.items[i].details.append(ProjectChecklistSubItemDetail(title: raw))
        p.items[i].details = p.items[i].details.withIncompleteDetailsFirst()
        store.upsertProjectChecklist(p)
        newDetailTextBySubItemId[subItemId] = ""
    }

    private func setDetailCompleted(subItemId: String, detailId: String, completed: Bool) {
        guard var p = store.projectChecklists.first(where: { $0.id == project.id }),
              let si = p.items.firstIndex(where: { $0.id == subItemId }),
              let di = p.items[si].details.firstIndex(where: { $0.id == detailId })
        else { return }
        p.items[si].details[di].isCompleted = completed
        p.items[si].details[di].completedAtYmd = completed ? LocalCalendarDate.localYmd(Date()) : nil
        p.items[si].details = p.items[si].details.withIncompleteDetailsFirst()
        store.upsertProjectChecklist(p)
    }

    private func deleteDetail(subItemId: String, detailId: String) {
        guard var p = store.projectChecklists.first(where: { $0.id == project.id }),
              let si = p.items.firstIndex(where: { $0.id == subItemId })
        else { return }
        p.items[si].details.removeAll { $0.id == detailId }
        store.upsertProjectChecklist(p)
    }

    // MARK: 子任务排序（仅行首图标可拖，避免 List.onMove 整行抢手势）

    private func subItemDragExportString(incompleteSection: Bool, id: String) -> String {
        (incompleteSection ? "subopen|" : "subdone|") + id
    }

    private func parseSubItemDragImport(_ raw: String) -> (incompleteSection: Bool, id: String)? {
        if raw.hasPrefix("subopen|") {
            return (true, String(raw.dropFirst("subopen|".count)))
        }
        if raw.hasPrefix("subdone|") {
            return (false, String(raw.dropFirst("subdone|".count)))
        }
        return nil
    }

    // MARK: 细节排序 / 跨子任务拖移（仅松手提交，避免 List 与系统拖移叠加状态机）

    private func detailDragExport(subItemId: String, detailId: String) -> String {
        "subdetail|\(project.id)|\(subItemId)|\(detailId)"
    }

    private func parseDetailDragImport(_ raw: String) -> (subItemId: String, detailId: String)? {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "subdetail", parts[1] == project.id else { return nil }
        return (parts[2], parts[3])
    }

    /// 栅格化细节行为固定尺寸 NSImage，与子任务拖影走同样的 AppKit 拖移路径。
    private func rasterizeDetailDragPreviewIfNeeded(
        key: String,
        title: String,
        detailDone: Bool,
        rowW: CGFloat
    ) {
        if detailDragPreviewBitmapKey == key, detailDragPreviewBitmap != nil { return }
        let body = DetailDragCardRasterBody(
            title: title,
            detailDone: detailDone,
            rowW: rowW
        )
        let renderer = ImageRenderer(content: body)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.proposedSize = ProposedViewSize(width: rowW, height: nil)
        guard let img = renderer.nsImage else { return }
        detailDragPreviewBitmap = img
        detailDragPreviewBitmapKey = key
    }

    private func prepareDetailMacDragSession(
        subItemId: String,
        detail: ProjectChecklistSubItemDetail
    ) {
        let key = "\(subItemId)|\(detail.id)"
        detailLiveDragKey = key
        let detailDone = subItemFromLive(subItemId)?.details.first(where: { $0.id == detail.id })?.isCompleted ?? false
        let rowW = subItemCardSizeById[subItemId]?.width ?? 300
        rasterizeDetailDragPreviewIfNeeded(
            key: key,
            title: detail.title,
            detailDone: detailDone,
            rowW: max(rowW - 12, 200)
        )
    }

    private func finishDetailDragAndClearTracking() {
        var noAnim = Transaction()
        noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            detailLiveDragKey = nil
            detailDragPreviewBitmap = nil
            detailDragPreviewBitmapKey = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                self.detailLiveDragKey = nil
                self.detailDragPreviewBitmap = nil
                self.detailDragPreviewBitmapKey = nil
            }
        }
    }

    private func detailHandleDrop(_ items: [String], insertBeforeDetailId: String?, hostSubItemId: String) -> Bool {
        guard let raw = items.first,
              let (fromSubId, dragDetailId) = parseDetailDragImport(raw)
        else { return false }
        if let b = insertBeforeDetailId, b == dragDetailId, fromSubId == hostSubItemId { return false }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            store.moveProjectChecklistSubItemDetail(
                projectId: project.id,
                fromSubItemId: fromSubId,
                toSubItemId: hostSubItemId,
                detailId: dragDetailId,
                beforeDetailId: insertBeforeDetailId
            )
        }
        finishDetailDragAndClearTracking()
        return true
    }

    private func subItemSortedPeerIds(incompleteSection: Bool) -> [String] {
        let peers = incompleteSection
            ? (live?.items ?? []).filter { !$0.isCompleted }.sorted(by: ProjectChecklist.sortSubItemsOpen)
            : (live?.items ?? []).filter(\.isCompleted).sorted(by: ProjectChecklist.sortSubItemsDone)
        return peers.map(\.id)
    }

    /// 若 `draggedId` 已在 `beforeNeighborId` 正上方，则无需再写盘。
    private func subItemIsImmediatelyBefore(draggedId: String, beforeNeighborId: String, incompleteSection: Bool) -> Bool {
        let ids = subItemSortedPeerIds(incompleteSection: incompleteSection)
        guard let iDrag = ids.firstIndex(of: draggedId), let iBefore = ids.firstIndex(of: beforeNeighborId) else {
            return false
        }
        return iDrag == iBefore - 1
    }

    private func reorderSubItemMoveBefore(draggedId: String, beforeNeighborId: String, incompleteSection: Bool) {
        if subItemIsImmediatelyBefore(draggedId: draggedId, beforeNeighborId: beforeNeighborId, incompleteSection: incompleteSection) {
            return
        }
        let peers = incompleteSection
            ? (live?.items ?? []).filter { !$0.isCompleted }.sorted(by: ProjectChecklist.sortSubItemsOpen)
            : (live?.items ?? []).filter(\.isCompleted).sorted(by: ProjectChecklist.sortSubItemsDone)
        var ids = peers.map(\.id)
        guard let from = ids.firstIndex(of: draggedId), let to = ids.firstIndex(of: beforeNeighborId) else { return }
        if from == to { return }
        ids.remove(at: from)
        let toAdj = from < to ? to - 1 : to
        ids.insert(draggedId, at: toAdj)
        store.applySubItemOrder(projectId: project.id, incompleteSection: incompleteSection, orderedIds: ids)
    }

    private func reorderSubItemToEnd(draggedId: String, incompleteSection: Bool) {
        let ids = subItemSortedPeerIds(incompleteSection: incompleteSection)
        if ids.last == draggedId { return }
        var moved = ids
        guard let from = moved.firstIndex(of: draggedId) else { return }
        moved.remove(at: from)
        moved.append(draggedId)
        store.applySubItemOrder(projectId: project.id, incompleteSection: incompleteSection, orderedIds: moved)
    }

    private func clearSubItemLiveDragTracking() {
        subItemLiveDragId = nil
        subItemLiveDragIncompleteSection = nil
        subItemLiveReorderTargetBeforeId = nil
        subItemLiveReorderTargetAtEnd = false
        detailLiveDragKey = nil
        detailDragPreviewBitmap = nil
        detailDragPreviewBitmapKey = nil
        subItemDragFrozenCardSize = nil
        subItemDragPreviewBitmap = nil
        subItemDragPreviewBitmapItemId = nil
    }

    /// 拖放落点后系统可能再次构造/销毁预览并触发 `onAppear`，把 `subItemLiveDragId` 写回；用无动画清除并在稍后几帧再清一次，避免虚线槽卡住。
    private func finishSubItemDragAndClearTracking() {
        var noAnim = Transaction()
        noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            clearSubItemLiveDragTracking()
        }
        DispatchQueue.main.async {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                self.clearSubItemLiveDragTracking()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                self.clearSubItemLiveDragTracking()
            }
        }
    }

    /// 未松手时：指针悬停在某行上方则实时把拖动项插到该行之前（与滴答清单类似）。
    private func subItemTryLiveReorderInsertBefore(targetBeforeId: String, incompleteSection: Bool) {
        guard let d = subItemLiveDragId,
              let sec = subItemLiveDragIncompleteSection,
              sec == incompleteSection,
              d != targetBeforeId else { return }
        if subItemLiveReorderTargetBeforeId == targetBeforeId, !subItemLiveReorderTargetAtEnd {
            return
        }
        if subItemIsImmediatelyBefore(draggedId: d, beforeNeighborId: targetBeforeId, incompleteSection: incompleteSection) {
            subItemLiveReorderTargetBeforeId = targetBeforeId
            subItemLiveReorderTargetAtEnd = false
            return
        }
        subItemLiveReorderTargetBeforeId = targetBeforeId
        subItemLiveReorderTargetAtEnd = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.87)) {
            reorderSubItemMoveBefore(draggedId: d, beforeNeighborId: targetBeforeId, incompleteSection: incompleteSection)
        }
    }

    private func subItemTryLiveReorderToEnd(incompleteSection: Bool) {
        guard let d = subItemLiveDragId,
              let sec = subItemLiveDragIncompleteSection,
              sec == incompleteSection else { return }
        let ids = subItemSortedPeerIds(incompleteSection: incompleteSection)
        if ids.last == d {
            subItemLiveReorderTargetBeforeId = nil
            subItemLiveReorderTargetAtEnd = true
            return
        }
        if subItemLiveReorderTargetAtEnd, subItemLiveReorderTargetBeforeId == nil {
            return
        }
        subItemLiveReorderTargetBeforeId = nil
        subItemLiveReorderTargetAtEnd = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.87)) {
            reorderSubItemToEnd(draggedId: d, incompleteSection: incompleteSection)
        }
    }

    private func subItemHandleDrop(_ items: [String], insertBeforeId: String?, incompleteSection: Bool) -> Bool {
        guard let raw = items.first, let (sec, dragId) = parseSubItemDragImport(raw), sec == incompleteSection else {
            return false
        }
        if let before = insertBeforeId {
            guard dragId != before else { return false }
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            if let before = insertBeforeId {
                reorderSubItemMoveBefore(draggedId: dragId, beforeNeighborId: before, incompleteSection: incompleteSection)
            } else {
                reorderSubItemToEnd(draggedId: dragId, incompleteSection: incompleteSection)
            }
        }
        finishSubItemDragAndClearTracking()
        return true
    }

    private func subItemDropAtEndOfSection(incompleteSection: Bool) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 18)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                subItemHandleDrop(items, insertBeforeId: nil, incompleteSection: incompleteSection)
            } isTargeted: { targeted in
                if incompleteSection {
                    if targeted {
                        subItemTryLiveReorderToEnd(incompleteSection: true)
                    } else {
                        subItemLiveReorderTargetAtEnd = false
                    }
                } else {
                    if targeted {
                        subItemTryLiveReorderToEnd(incompleteSection: false)
                    } else {
                        subItemLiveReorderTargetAtEnd = false
                    }
                }
            }
    }

    /// macOS：`.help` 为系统悬停 tooltip；单行文本框展示不全时可将指针悬停在标题上以查看全文。
    private func editableTitleHoverHelp(_ fullText: String, whenEmpty: String) -> String {
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return whenEmpty }
        return fullText
    }

    private func subItemPrioritySymbol(_ p: ProjectChecklistSubItemPriority) -> String {
        switch p {
        case .none: return ""
        case .low: return "arrow.down.circle.fill"
        case .medium: return "equal.circle.fill"
        case .high: return "exclamationmark.3"
        }
    }

    /// 生成固定像素尺寸的拖影（仅卡片本身，不含 leadPad），避免 draggingFrame 产生大负偏移导致松手飞走。
    private func rasterizeSubItemDragPreviewIfNeeded(
        itemId: String,
        sub: ProjectChecklistSubItem,
        cardW: CGFloat,
        cardH: CGFloat,
        completedLook: Bool
    ) {
        if subItemDragPreviewBitmapItemId == itemId, subItemDragPreviewBitmap != nil { return }
        let pr = sub.priority
        let sym = pr == .none ? nil : subItemPrioritySymbol(pr)
        let body = SubItemDragCardRasterBody(
            sub: sub,
            cardW: cardW,
            cardH: cardH,
            completedLook: completedLook,
            prioritySymbolName: sym
        )
        let renderer = ImageRenderer(content: body)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.proposedSize = ProposedViewSize(width: cardW, height: cardH)
        guard let img = renderer.nsImage else { return }
        subItemDragPreviewBitmap = img
        subItemDragPreviewBitmapItemId = itemId
    }

    /// AppKit 起拖前：冻结卡片尺寸、更新实时排序状态并栅格化拖影（避免把大块逻辑写在 `subItemRow` 里导致类型检查超时）。
    private func prepareSubItemMacDragSession(
        item: ProjectChecklistSubItem,
        incompleteSection: Bool,
        completedLook: Bool
    ) {
        if subItemDragFrozenCardSize == nil {
            subItemDragFrozenCardSize = subItemCardSizeById[item.id] ?? CGSize(width: 320, height: 140)
        }
        subItemLiveDragId = item.id
        subItemLiveDragIncompleteSection = incompleteSection
        guard let fzEntry = subItemDragFrozenCardSize else { return }
        let cw = max(fzEntry.width, 160)
        let ch = max(fzEntry.height, 72)
        let dragSub = subItemFromLive(item.id) ?? item
        rasterizeSubItemDragPreviewIfNeeded(
            itemId: item.id,
            sub: dragSub,
            cardW: cw,
            cardH: ch,
            completedLook: completedLook
        )
    }

    /// Web 式排序：原位置留白槽（虚线框），真实内容用 opacity 隐藏以保留布局与高度；须放在 `ZStack` 顶层，勿叠在整卡 `opacity(0)` 之后以免被一起画透明。
    private func subItemDragSourcePlaceholder(completedLook: Bool, cornerRadius: CGFloat = 10) -> some View {
        let border = completedLook ? Color.secondary.opacity(0.48) : Color.accentColor.opacity(0.52)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [6, 5]))
            }
    }

    private func subItemRow(item: ProjectChecklistSubItem, completedLook: Bool) -> some View {
        let sub = subItemFromLive(item.id) ?? item
        let done = sub.isCompleted
        let subTitleLive = subItemFromLive(item.id)?.title ?? ""
        let pr = subItemFromLive(item.id)?.priority ?? .none
        let incompleteSection = !completedLook
        let detailsExpanded = subItemDetailsSectionExpanded(subItemId: item.id, completedLook: completedLook)

        // 热点 = 手柄图标在卡片内的中心：padding(8) + horizontal(3) + 半宽(14) ≈ 25pt
        let subItemMacDragHotSpot = NSPoint(x: 8 + 3 + 14, y: 8 + 4 + 16)

        let subCardStack = VStack(alignment: .leading, spacing: 8) {
            if completedLook {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green.opacity(0.85))
                    Text("已完成子任务")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.32), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("已完成子任务")
            }

            // 与细节行一致：`firstTextBaseline` 易让 SF Symbol 视觉错位，图标列用垂直居中 + 统一行高。
            HStack(alignment: .center, spacing: 4) {
                ZStack {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 32, alignment: .center)
                    SubItemDragHandleMac(
                        dragImage: $subItemDragPreviewBitmap,
                        pasteboardString: subItemDragExportString(incompleteSection: incompleteSection, id: item.id),
                        hotSpotInImage: subItemMacDragHotSpot,
                        onPrepare: { prepareSubItemMacDragSession(item: item, incompleteSection: incompleteSection, completedLook: completedLook) },
                        onDragSessionEnd: { finishSubItemDragAndClearTracking() },
                        toolTip: "按住此图标拖动，调整子任务顺序（勿从标题栏拖动）"
                    )
                    .frame(width: 28, height: 32)
                }
                .contentShape(Rectangle())
                .accessibilityLabel("排序：拖动调整子任务顺序")
                .help("按住此图标拖动，调整子任务顺序（勿从标题栏拖动）")

                if pr != .none {
                    Image(systemName: subItemPrioritySymbol(pr))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(completedLook ? Color.secondary : Color.accentColor)
                        .frame(width: 16, height: 32, alignment: .center)
                        .accessibilityLabel("优先级：\(pr.displayName)")
                }

                Toggle("", isOn: Binding(
                    get: { subItemFromLive(item.id)?.isCompleted ?? false },
                    set: { v in
                        if v {
                            if !completedLook {
                                let liveSub = subItemFromLive(item.id) ?? item
                                let allDetailsDone = liveSub.details.allSatisfy(\.isCompleted)
                                if allDetailsDone {
                                    store.setProjectChecklistSubItemCompleted(projectId: project.id, subItemId: item.id, completed: true)
                                    subItemDetailsExpanded[item.id] = false
                                } else {
                                    subItemCompleteConfirmationSubItemId = item.id
                                }
                            } else {
                                store.setProjectChecklistSubItemCompleted(projectId: project.id, subItemId: item.id, completed: true)
                                subItemDetailsExpanded[item.id] = false
                            }
                        } else {
                            store.setProjectChecklistSubItemCompleted(projectId: project.id, subItemId: item.id, completed: false)
                            subItemDetailsExpanded.removeValue(forKey: item.id)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(done ? "标记为未完成" : "标记为已完成（若有未完成的细节将询问是否一并完成）")

                LiveSubItemTitleField(
                    projectId: project.id,
                    itemId: item.id,
                    initialTitle: sub.title,
                    completedLook: completedLook,
                    done: done,
                    hoverHelp: editableTitleHoverHelp(subTitleLive, whenEmpty: "暂无标题，右键可删除或添加提醒；有内容时悬停可看全文。")
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

                HStack(spacing: 4) {
                    if !detailsExpanded, !sub.details.isEmpty {
                        Text("\(sub.details.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.14)))
                            .accessibilityLabel("\(sub.details.count) 条细节")
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(detailsExpanded ? 90 : 0))
                        .frame(width: 20, height: 28, alignment: .center)
                }
                .help(detailsExpanded ? "折叠细节" : "展开细节")
                .accessibilityElement(children: .combine)
                .accessibilityLabel(detailsExpanded ? "折叠细节" : "展开细节")
                .accessibilityHint(detailsExpanded ? "点按以折叠细节" : "点按以展开细节")
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        Color(nsColor: .quaternaryLabelColor)
                            .opacity(hoveredSubItemId == item.id ? 0.32 : 0)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onTapGesture {
                toggleSubItemDetailsExpansion(subItemId: item.id, completedLook: completedLook)
            }
            .onHover { hovering in
                if hovering {
                    hoveredSubItemId = item.id
                } else if hoveredSubItemId == item.id {
                    hoveredSubItemId = nil
                }
            }

            if detailsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sub.details) { detail in
                        subItemDetailRow(
                            subItemId: item.id,
                            detail: detail,
                            completedLook: completedLook
                        )
                    }

                    if !completedLook {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 12, height: 28, alignment: .center)
                            TextField("添加任务细节…", text: Binding(
                                get: { newDetailTextBySubItemId[item.id] ?? "" },
                                set: { newDetailTextBySubItemId[item.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit { addDetail(subItemId: item.id) }
                            Button("添加") {
                                addDetail(subItemId: item.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(
                                (newDetailTextBySubItemId[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(.leading, 4)
                .padding(.top, 1)
                .dropDestination(for: String.self) { items, _ in
                    detailHandleDrop(items, insertBeforeDetailId: nil, hostSubItemId: item.id)
                } isTargeted: { _ in }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: detailsExpanded)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    completedLook
                        ? Color(nsColor: .quaternaryLabelColor).opacity(0.14)
                        : Color.accentColor.opacity(0.10)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    completedLook
                        ? Color.secondary.opacity(0.22)
                        : Color.accentColor.opacity(0.42),
                    lineWidth: completedLook ? 1 : 1.25
                )
        )
        .overlay(alignment: .leading) {
            if completedLook {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 4)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: SubItemCardSizeKey.self,
                        value: {
                            if subItemLiveDragId == item.id {
                                // 不再发 `[:]`：合并后会丢掉该 id，拖影下一帧读到更小默认尺寸。拖动中始终上报「冻结」或保底宽度。
                                let w: CGFloat
                                let h: CGFloat
                                if let fz = subItemDragFrozenCardSize {
                                    w = fz.width
                                    h = fz.height
                                } else {
                                    let hint = subItemCardSizeById[item.id]?.width ?? geo.size.width
                                    let hh = subItemCardSizeById[item.id]?.height ?? geo.size.height
                                    w = max(geo.size.width, hint, 240)
                                    h = max(geo.size.height, hh, 72)
                                }
                                return [item.id: CGSize(width: w, height: h)]
                            }
                            return [item.id: CGSize(width: geo.size.width, height: geo.size.height)]
                        }()
                    )
            }
            .allowsHitTesting(false)
        }
        .opacity(subItemLiveDragId == item.id ? 0 : 1)

        return ZStack(alignment: .topLeading) {
            subCardStack
            if subItemLiveDragId == item.id {
                subItemDragSourcePlaceholder(completedLook: completedLook)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            if let raw = items.first, raw.hasPrefix("subdetail|") {
                let firstDetailId = (subItemFromLive(item.id) ?? item).details.first?.id
                return detailHandleDrop(items, insertBeforeDetailId: firstDetailId, hostSubItemId: item.id)
            }
            return subItemHandleDrop(items, insertBeforeId: item.id, incompleteSection: incompleteSection)
        } isTargeted: { targeted in
            if incompleteSection {
                if targeted {
                    subItemTryLiveReorderInsertBefore(targetBeforeId: item.id, incompleteSection: true)
                } else if subItemLiveReorderTargetBeforeId == item.id {
                    subItemLiveReorderTargetBeforeId = nil
                }
            } else {
                if targeted {
                    subItemTryLiveReorderInsertBefore(targetBeforeId: item.id, incompleteSection: false)
                } else if subItemLiveReorderTargetBeforeId == item.id {
                    subItemLiveReorderTargetBeforeId = nil
                }
            }
        }
        .contextMenu {
            let base = live ?? project
            Button("添加定时提醒…") {
                onComposeOneTimeReminder(
                    OneTimeReminder.draftFromChecklistHint(
                        checklistTitle: base.title,
                        subtaskTitle: subItemFromLive(item.id)?.title,
                        dateYmd: base.preferredReminderDateYmd()
                    )
                )
            }
            Menu("优先级") {
                ForEach(ProjectChecklistSubItemPriority.allCases, id: \.self) { prOpt in
                    Button(prOpt.displayName) {
                        store.setProjectChecklistSubItemPriority(projectId: project.id, subItemId: item.id, priority: prOpt)
                    }
                }
            }
            Divider()
            Button("删除子任务…", role: .destructive) {
                deleteSubItem(id: item.id)
            }
        }
    }

    private func subItemDetailRow(
        subItemId: String,
        detail: ProjectChecklistSubItemDetail,
        completedLook: Bool
    ) -> some View {
        let detailDone = subItemFromLive(subItemId)?.details.first(where: { $0.id == detail.id })?.isCompleted ?? false
        let detailTitleLive = subItemFromLive(subItemId)?.details.first(where: { $0.id == detail.id })?.title ?? ""
        let detailHoverKey = "\(subItemId)|\(detail.id)"
        // 热点：手柄在行内的中心 padding(.horizontal,3) + 半宽(11) ≈ 14
        let detailHotSpot = NSPoint(x: 3 + 11, y: 4 + 14)

        // `.firstTextBaseline` 会让两个 SF Symbol 按「字体基线」贴齐，与视觉中心不一致；图标列用垂直居中 + 同一行高更整齐。
        let detailRow = HStack(alignment: .center, spacing: 6) {
            ZStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 28, alignment: .center)
                SubItemDragHandleMac(
                    dragImage: $detailDragPreviewBitmap,
                    pasteboardString: detailDragExport(subItemId: subItemId, detailId: detail.id),
                    hotSpotInImage: detailHotSpot,
                    onPrepare: { prepareDetailMacDragSession(subItemId: subItemId, detail: detail) },
                    onDragSessionEnd: { finishDetailDragAndClearTracking() },
                    toolTip: "拖动可排序，或拖到其他子任务下"
                )
                .frame(width: 22, height: 28)
            }
            .contentShape(Rectangle())
            .accessibilityLabel("排序：拖动细节")
            .help("拖动可排序，或拖到其他子任务下")

            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12, height: 28, alignment: .center)
            Toggle("", isOn: Binding(
                get: {
                    subItemFromLive(subItemId)?.details.first(where: { $0.id == detail.id })?.isCompleted ?? false
                },
                set: { setDetailCompleted(subItemId: subItemId, detailId: detail.id, completed: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(detailDone ? "标记细节为未完成" : "标记细节为已完成")

            if detailDone {
                Text("已完成")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.16)))
                    .accessibilityHidden(true)
            }

            LiveDetailTitleField(
                projectId: project.id,
                subItemId: subItemId,
                detailId: detail.id,
                initialTitle: detail.title,
                completedLook: completedLook,
                detailDone: detailDone,
                hoverHelp: editableTitleHoverHelp(detailTitleLive, whenEmpty: "暂无细节标题，右键可删除；有内容时悬停可查看全文。")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    detailDone
                        ? Color.secondary.opacity(0.12)
                        : Color(nsColor: .quaternaryLabelColor)
                        .opacity(hoveredDetailKey == detailHoverKey ? 0.30 : 0)
                )
        )
        .overlay(alignment: .leading) {
            if detailDone {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, 1)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            if hovering {
                hoveredDetailKey = detailHoverKey
            } else if hoveredDetailKey == detailHoverKey {
                hoveredDetailKey = nil
            }
        }
        .opacity(detailLiveDragKey == detailHoverKey ? 0 : 1)

        return ZStack(alignment: .topLeading) {
            detailRow
            if detailLiveDragKey == detailHoverKey {
                subItemDragSourcePlaceholder(completedLook: completedLook, cornerRadius: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            detailHandleDrop(items, insertBeforeDetailId: detail.id, hostSubItemId: subItemId)
        } isTargeted: { _ in }
        .contextMenu {
            Button("删除该细节…", role: .destructive) {
                deleteDetail(subItemId: subItemId, detailId: detail.id)
            }
        }
    }
}

// MARK: - 子任务/细节标题输入（List 内避免直绑 Store 失焦）

/// `List` 行里逐字 `upsert` 会整表刷新导致不能输入；本地 `State` + 短防抖写盘。
private struct LiveSubItemTitleField: View {
    @Environment(EfficiencyStore.self) private var store
    let projectId: String
    let itemId: String
    let completedLook: Bool
    let done: Bool
    let hoverHelp: String

    @State private var text: String
    @State private var saveWork: Task<Void, Never>?

    init(
        projectId: String,
        itemId: String,
        initialTitle: String,
        completedLook: Bool,
        done: Bool,
        hoverHelp: String
    ) {
        self.projectId = projectId
        self.itemId = itemId
        self.completedLook = completedLook
        self.done = done
        self.hoverHelp = hoverHelp
        _text = State(initialValue: initialTitle)
    }

    var body: some View {
        TextField("", text: $text, prompt: Text("子任务标题").foregroundStyle(.tertiary))
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .font(.callout.weight(completedLook ? .regular : .medium))
            .foregroundStyle(done ? Color.secondary : Color.primary)
            .lineLimit(1)
            .accessibilityLabel("子任务标题")
            .help(hoverHelp)
            .onChange(of: text) { _, new in
                scheduleSave(new)
            }
            .onSubmit { flushSave() }
            .onDisappear {
                saveWork?.cancel()
                flushSave()
            }
    }

    private func scheduleSave(_ value: String) {
        saveWork?.cancel()
        saveWork = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            persist(value)
        }
    }

    private func flushSave() {
        saveWork?.cancel()
        saveWork = nil
        persist(text)
    }

    private func persist(_ title: String) {
        guard var p = store.projectChecklists.first(where: { $0.id == projectId }),
              let i = p.items.firstIndex(where: { $0.id == itemId }),
              p.items[i].title != title
        else { return }
        p.items[i].title = title
        store.upsertProjectChecklist(p)
    }
}

private struct LiveDetailTitleField: View {
    @Environment(EfficiencyStore.self) private var store
    let projectId: String
    let subItemId: String
    let detailId: String
    let completedLook: Bool
    let detailDone: Bool
    let hoverHelp: String

    @State private var text: String
    @State private var saveWork: Task<Void, Never>?

    init(
        projectId: String,
        subItemId: String,
        detailId: String,
        initialTitle: String,
        completedLook: Bool,
        detailDone: Bool,
        hoverHelp: String
    ) {
        self.projectId = projectId
        self.subItemId = subItemId
        self.detailId = detailId
        self.completedLook = completedLook
        self.detailDone = detailDone
        self.hoverHelp = hoverHelp
        _text = State(initialValue: initialTitle)
    }

    var body: some View {
        TextField("", text: $text, prompt: Text("细节标题").foregroundStyle(.tertiary))
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .font(.subheadline.weight(completedLook && detailDone ? .regular : .medium))
            .foregroundStyle(detailDone ? Color.secondary : Color.primary)
            .lineLimit(1)
            .accessibilityLabel("任务细节标题")
            .help(hoverHelp)
            .onChange(of: text) { _, new in
                scheduleSave(new)
            }
            .onSubmit { flushSave() }
            .onDisappear {
                saveWork?.cancel()
                flushSave()
            }
    }

    private func scheduleSave(_ value: String) {
        saveWork?.cancel()
        saveWork = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            persist(value)
        }
    }

    private func flushSave() {
        saveWork?.cancel()
        saveWork = nil
        persist(text)
    }

    private func persist(_ title: String) {
        guard var p = store.projectChecklists.first(where: { $0.id == projectId }),
              let si = p.items.firstIndex(where: { $0.id == subItemId }),
              let di = p.items[si].details.firstIndex(where: { $0.id == detailId }),
              p.items[si].details[di].title != title
        else { return }
        p.items[si].details[di].title = title
        store.upsertProjectChecklist(p)
    }
}

// MARK: - 新建 / 编辑标题与日期

private struct ProjectChecklistEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: ProjectChecklist
    let isNew: Bool
    var onSave: (ProjectChecklist) -> Void

    @State private var title: String
    @State private var tag: ProjectChecklistTag
    @State private var useStart: Bool
    @State private var useDue: Bool
    @State private var startDate: Date
    @State private var dueDate: Date

    init(draft: ProjectChecklist, isNew: Bool, onSave: @escaping (ProjectChecklist) -> Void) {
        self.draft = draft
        self.isNew = isNew
        self.onSave = onSave
        _title = State(initialValue: draft.title)
        _tag = State(initialValue: draft.tag)
        let cal = Calendar.current
        let s = draft.startYmd.flatMap { LocalCalendarDate.parseLocalYmd($0, calendar: cal) } ?? cal.startOfDay(for: Date())
        let d = draft.dueYmd.flatMap { LocalCalendarDate.parseLocalYmd($0, calendar: cal) } ?? cal.startOfDay(for: Date())
        _startDate = State(initialValue: s)
        _dueDate = State(initialValue: d)
        _useStart = State(initialValue: draft.startYmd != nil)
        _useDue = State(initialValue: draft.dueYmd != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "新建需求清单" : "编辑需求清单")
                .font(.title2.bold())
                .padding(.bottom, 8)

            ScrollView {
                Form {
                    Section {
                        TextField("标题", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 2)
                    } header: {
                        Text("标题")
                    }

                    Section {
                        Text("可不选：保持「无」则侧栏仅显示空心小圆，月历条为默认橙色。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 10) {
                            ForEach(ProjectChecklistTag.allCases, id: \.self) { t in
                                Button {
                                    tag = t
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(t == .none ? Color.secondary.opacity(0.14) : t.dotFill)
                                            .frame(width: 26, height: 26)
                                        if t == .none {
                                            Image(systemName: "slash.circle")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.accentColor.opacity(tag == t ? 0.95 : 0), lineWidth: 2.5)
                                            .frame(width: 30, height: 30)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help(t.displayName)
                            }
                        }
                    } header: {
                        Text("颜色（可选）")
                    }

                    Section {
                        Toggle(isOn: $useStart) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("启用开始日")
                                    .font(.body.weight(.medium))
                                Text("月历从该日起显示区间；若只填开始日，则仅在当天出现在日历中。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if useStart {
                            DatePicker("开始日", selection: $startDate, displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "zh-Hans"))
                        }

                        Toggle(isOn: $useDue) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("启用截止日")
                                    .font(.body.weight(.medium))
                                Text("可与开始日组成闭区间；若只填截止日，则仅在当天出现在日历中。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if useDue {
                            DatePicker("截止日", selection: $dueDate, displayedComponents: .date)
                                .environment(\.locale, Locale(identifier: "zh-Hans"))
                        }
                    } header: {
                        Text("日历区间")
                    }
                }
                .formStyle(.grouped)
            }
            .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 480)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(isNew ? "创建" : "保存") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(minWidth: 640, idealWidth: 720, maxWidth: 900, minHeight: 520, idealHeight: 580)
    }

    private func save() {
        let cal = Calendar.current
        var next = draft
        next.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        next.tag = tag
        next.startYmd = useStart ? LocalCalendarDate.localYmd(startDate, calendar: cal) : nil
        next.dueYmd = useDue ? LocalCalendarDate.localYmd(dueDate, calendar: cal) : nil
        next.normalizeDateOrder()
        onSave(next)
        dismiss()
    }
}

// MARK: - SwiftUI Preview（Canvas：选 `ProjectChecklistsView.swift` → Resume）

#if DEBUG
@MainActor
private enum ProjectChecklistsViewPreviewStore {
    static func make() -> EfficiencyStore {
        let s = EfficiencyStore()
        let created = "2026-04-02"
        let itemA = ProjectChecklistSubItem(
            id: "pv-open-a",
            title: "子任务 A · 多条细节（看布局 / 拖移判定）",
            isCompleted: false,
            priority: .high,
            listOrder: 0,
            details: [
                ProjectChecklistSubItemDetail(id: "pv-da-0", title: "细节一"),
                ProjectChecklistSubItemDetail(
                    id: "pv-da-1",
                    title: "细节二 · 较长标题与手柄、输入框水平对齐"
                ),
                ProjectChecklistSubItemDetail(id: "pv-da-2", title: "细节三"),
            ]
        )
        let itemB = ProjectChecklistSubItem(
            id: "pv-open-b",
            title: "子任务 B · 跨卡拖细节目标",
            isCompleted: false,
            priority: .none,
            listOrder: 1,
            details: [
                ProjectChecklistSubItemDetail(id: "pv-db-0", title: "B 下已有细节"),
            ]
        )
        s.projectChecklists = [
            ProjectChecklist(
                id: "pv-proj-0",
                title: "预览清单 · Alpha",
                startYmd: nil,
                dueYmd: nil,
                createdAt: created,
                isCompleted: false,
                tag: .blue,
                sidebarOrder: 0,
                items: [itemA, itemB]
            ),
            ProjectChecklist(
                id: "pv-proj-1",
                title: "预览清单 · Beta（窄侧栏对照）",
                startYmd: nil,
                dueYmd: nil,
                createdAt: created,
                isCompleted: false,
                tag: .mint,
                sidebarOrder: 1,
                items: [
                    ProjectChecklistSubItem(
                        id: "pv-open-c",
                        title: "仅一条子任务",
                        listOrder: 0,
                        details: []
                    ),
                ]
            ),
        ]
        return s
    }
}

// 若 Canvas 仍卡住：Product → Clean Build Folder，并只保留一个 preview 运行。
#Preview("需求清单") {
    ProjectChecklistsView()
        .environment(ProjectChecklistsViewPreviewStore.make())
        .frame(width: 960, height: 640)
}
#endif
