//
//  MiniTools_SwiftUIApp.swift
//  MiniTools-SwiftUI
//
//  Created by 石山岭 on 2026/3/31.
//

import SwiftUI

@main
struct MiniTools_SwiftUIApp: App {
    @State private var store = EfficiencyStore()

    init() {
        // AppKit 悬停提示（`.help`、NSView.toolTip）默认约 1000ms 后才出现；改用更短初始延迟（毫秒）。
        // 见 `NSInitialToolTipDelay`；`registerDefaults` 不覆盖用户已在「终端 defaults」里写过的值。
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 400])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 720, minHeight: 520)
                .onOpenURL { url in
                    Task { await WidgetURLHandler.handle(url, store: store) }
                }
        }
        // 首次打开（无上次关闭时保存的尺寸）时使用；用户仍可自由缩放。
        .defaultSize(width: 960, height: 720)
    }
}
