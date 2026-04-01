//
//  ContentView.swift
//  MiniTools-SwiftUI
//
//  Created by 石山岭 on 2026/3/31.
//

import SwiftUI

struct ContentView: View {
    @Environment(EfficiencyStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notifier = NotificationScheduler.shared

    @State private var showLaunchSplash = true

    var body: some View {
        ZStack {
            launchableContent
            if showLaunchSplash {
                LaunchSplashView()
                    .transition(.opacity)
            }
        }
        .task {
            await store.loadInitial()
            withAnimation(.easeOut(duration: 0.35)) {
                showLaunchSplash = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await notifier.refreshAuthorizationStatus()
                await store.refreshRecurringAndHourlyNotifications()
            }
        }
        .onAppear {
            NotificationScheduler.shared.efficiencyStore = store
        }
    }

    @ViewBuilder
    private var launchableContent: some View {
        VStack(spacing: 0) {
            if notifier.isAuthorizationDenied {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.orange)
                    Text(
                        "系统通知已关闭：提醒无法在到达时刻由系统弹出。数据仍保存在本机；若要收到提醒，请在系统设置中为本应用开启通知。"
                    )
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("打开通知设置") {
                        SystemSettings.openNotificationsPane()
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
            }

            TabView {
                NavigationStack {
                    OneTimeRemindersView()
                }
                .tabItem { Label("定时提醒", systemImage: "bell.badge") }

                NavigationStack {
                    RecurringTasksView()
                }
                .tabItem { Label("例行任务", systemImage: "arrow.triangle.2.circlepath") }

                NavigationStack {
                    HourlyWindowTasksView()
                }
                .tabItem { Label("时段提醒", systemImage: "clock.arrow.2.circlepath") }

                NavigationStack {
                    TasksCalendarView()
                }
                .tabItem { Label("日历", systemImage: "calendar") }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(EfficiencyStore())
}
