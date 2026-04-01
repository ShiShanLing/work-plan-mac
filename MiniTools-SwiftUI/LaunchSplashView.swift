//
//  LaunchSplashView.swift
//  MiniTools-SwiftUI
//

import SwiftUI

/// 与 Expo 工程一致：优先使用 `SplashScreenLegacy`（含 iPad 的 `tablet_image` 4:3 启动图）。
/// 在窗口中取「最大内接 4:3」矩形展示全幅图，其余区域铺 `SplashScreenBackground`，避免手机式小 Logo 居中缩在中间。
struct LaunchSplashView: View {
    private static let launchAspectRatio: CGFloat = 4.0 / 3.0

    var body: some View {
        ZStack {
            Color("SplashScreenBackground")
                .ignoresSafeArea()
            Color.clear
                .aspectRatio(Self.launchAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    Image("SplashScreenLegacy")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        }
    }
}

#Preview("4:3 — iPad 类") {
    LaunchSplashView()
        .frame(width: 1024, height: 768)
}

#Preview("宽屏窗口") {
    LaunchSplashView()
        .frame(width: 1200, height: 700)
}

#Preview("竖屏手机比例") {
    LaunchSplashView()
        .frame(width: 390, height: 844)
}
