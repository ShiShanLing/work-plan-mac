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
    #if DEBUG
    @State private var showPurgeNotificationsConfirm = false
    #endif

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
        #if DEBUG
        .confirmationDialog(
            "如何处理本地通知？",
            isPresented: $showPurgeNotificationsConfirm,
            titleVisibility: .visible
        ) {
            Button("全部清空（含未来已排程），暂不重新排程", role: .destructive) {
                store.clearAllNotificationsOnlyPersistIds()
            }
            Button("清空后按当前任务重新排程", role: .destructive) {
                Task { await store.purgeAllNotificationQueueAndResync() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("两种方式都会删掉系统中尚未触发的全部提醒，并清空通知中心里本应用已送达的条目。前者在重启、回桌面后也不会自动再排程，直到你编辑某条任务或在通知里完成操作；后者会立刻为现有任务重新排队。")
        }
        #endif
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

            #if DEBUG
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "trash.circle")
                    .foregroundStyle(.secondary)
                Text("可一键清空本应用全部本地通知（含未来已排程）。可选只清空不排程，或清空后按当前任务重排。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("清除通知队列…") {
                    showPurgeNotificationsConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!store.hasCompletedInitialLoad)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.08))
            #endif

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
