//
//  MiniTools_SwiftUIApp.swift
//  MiniTools-SwiftUI
//
//  Created by 石山岭 on 2026/3/31.
//

import AppKit
import SwiftUI

/// macOS 应用入口：创建 `EfficiencyStore`、主窗口组（固定 id 便于深链复用窗口）。
@main
struct MiniTools_SwiftUIApp: App {
    @State private var store = EfficiencyStore()

    init() {
        // AppKit 悬停提示（`.help`、NSView.toolTip）默认约 1000ms 后才出现；改用更短初始延迟（毫秒）。
        // 见 `NSInitialToolTipDelay`；`registerDefaults` 不覆盖用户已在「终端 defaults」里写过的值。
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 400])
    }

    var body: some Scene {
        // 固定 id，便于小组件 URL 唤醒时 `openWindow` 在「无窗口」（如已 ⌘W 关窗）下重建窗口。
        WindowGroup(id: "main") {
            AppRootView(store: store)
        }
        .handlesExternalEvents(matching: Set(["*"]))
        // 首次打开（无上次关闭时保存的尺寸）时使用；用户仍可自由缩放。
        .defaultSize(width: 960, height: 720)
    }
}

// MARK: - 小组件 / URL：隐藏、最小化、关窗后仍需置前主窗口

/// 包住 `ContentView`：注入 Store、`openWindow` 召回主窗口，并把 `minitools://` 交给 `WidgetURLHandler`。
private struct AppRootView: View {
    var store: EfficiencyStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .environment(store)
            .frame(minWidth: 720, minHeight: 520)
            // 已有窗口时，把 minitools:// 交给当前场景，避免系统再开一个新窗口。
            .handlesExternalEvents(preferring: Set(["*"]), allowing: Set(["*"]))
            .onOpenURL { url in
                bringMainWindowToFront(openWindow: openWindow)
                Task { await WidgetURLHandler.handle(url, store: store) }
            }
    }

    private func bringMainWindowToFront(openWindow: OpenWindowAction) {
        // 延后到下一轮 RunLoop：与 WidgetKit 打开 URL 的时序更合拍。
        // 注意：最小化窗口的 `canBecomeKey` 为 false，不能只用 canBecomeKey 过滤，否则会误判为「无窗口」而 duplicate openWindow。
        DispatchQueue.main.async {
            let app = NSApplication.shared
            app.activate(ignoringOtherApps: true)
            app.unhide(nil)

            let candidates = app.windows.filter { w in
                w.level == .normal && !w.isSheet && w.styleMask.contains(.titled)
            }

            guard !candidates.isEmpty else {
                openWindow(id: "main")
                return
            }

            for w in candidates {
                if w.isMiniaturized {
                    w.deminiaturize(nil)
                }
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}
