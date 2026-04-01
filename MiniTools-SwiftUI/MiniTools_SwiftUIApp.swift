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
