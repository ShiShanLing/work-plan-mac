//
//  SubItemDragHandleMac.swift
//  MiniTools-SwiftUI
//
//  子任务排序手柄：用 AppKit 起拖，拖影为固定尺寸的 NSImage，避免 SwiftUI .draggable 宿主在跨行/跨投放区时压窄预览。
//

import AppKit
import SwiftUI

/// 覆盖在手柄图标上的透明视图，在拖动阈值后通过 `NSDraggingSession` 发起拖移。
struct SubItemDragHandleMac: NSViewRepresentable {
    @Binding var dragImage: NSImage?
    let pasteboardString: String
    let hotSpotInImage: NSPoint
    let onPrepare: () -> Void
    let onDragSessionEnd: () -> Void
    var toolTip: String = ""

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> DragHostNSView {
        let v = DragHostNSView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ nsView: DragHostNSView, context: Context) {
        let c = context.coordinator
        c.pasteboardString = pasteboardString
        c.hotSpotInImage = hotSpotInImage
        c.onPrepare = onPrepare
        c.onDragSessionEnd = onDragSessionEnd
        c.getDragImage = { dragImage }
        nsView.coordinator = c
        nsView.toolTip = toolTip.isEmpty ? nil : toolTip
    }

    final class Coordinator: NSObject, NSDraggingSource {
        var pasteboardString: String = ""
        var hotSpotInImage = NSPoint.zero
        var onPrepare: () -> Void = {}
        var onDragSessionEnd: () -> Void = {}
        var getDragImage: () -> NSImage? = { nil }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            if context == .outsideApplication { return [] }
            return [.copy, .move, .generic]
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

        // 最早时机：会话即将展示拖影之前
        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            session.animatesToStartingPositionsOnCancelOrFail = false
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            session.animatesToStartingPositionsOnCancelOrFail = false
            DispatchQueue.main.async { self.onDragSessionEnd() }
        }

        func beginDragging(from view: DragHostNSView, mouseDownInView: NSPoint, event: NSEvent) {
            onPrepare()
            guard let img = getDragImage(), img.size.width > 0.5, img.size.height > 0.5 else { return }

            let pb = NSPasteboardItem()
            pb.setString(pasteboardString, forType: .string)
            pb.setString(pasteboardString, forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
            pb.setString(pasteboardString, forType: NSPasteboard.PasteboardType("public.plain-text"))
            let dragItem = NSDraggingItem(pasteboardWriter: pb)

            let w = img.size.width
            let h = img.size.height
            let hx = hotSpotInImage.x
            let hy = hotSpotInImage.y

            // 整张图片作为 draggingFrame；热点决定鼠标按在图里的哪个位置。
            // 坐标系为 view-local（flipped），原点在手柄视图内，大图可以超出视图 bounds。
            dragItem.setDraggingFrame(
                NSRect(x: mouseDownInView.x - hx, y: mouseDownInView.y - hy, width: w, height: h),
                contents: img
            )

            let session = view.beginDraggingSession(with: [dragItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = false
        }
    }
}

final class DragHostNSView: NSView {
    var coordinator: SubItemDragHandleMac.Coordinator?
    private var mouseDownLocation: NSPoint?
    private var didBeginDragSession = false

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        didBeginDragSession = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, let coord = coordinator, !didBeginDragSession else { return }
        let cur = convert(event.locationInWindow, from: nil)
        let dx = cur.x - start.x
        let dy = cur.y - start.y
        guard dx * dx + dy * dy >= 4 else { return }
        didBeginDragSession = true
        coord.beginDragging(from: self, mouseDownInView: start, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        didBeginDragSession = false
    }
}
