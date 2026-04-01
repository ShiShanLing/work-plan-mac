//
//  LocalJSONStore.swift
//  MiniTools-SwiftUI
//

import Foundation
import MiniToolsCore
import OSLog

/// 主应用与小组件共用 App Group 内 JSON；失败时回退到本机 Application Support（无小组件同步）。
enum LocalJSONStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let fileNames = [
        "one_time_reminders.json",
        "recurring_tasks.json",
        "hourly_window_tasks.json",
    ]

    private static var legacyDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appending(path: "MiniTools-SwiftUI", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var directoryURL: URL {
        if let groupRoot = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            let dir = groupRoot.appending(path: MiniToolsDataIsolation.appGroupJSONDirectoryName, directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                migrateFromLegacyIfNeeded(into: dir)
            } else if !UserDefaults.standard.bool(forKey: "minitools_migrated_legacy_to_group") {
                migrateFromLegacyIfNeeded(into: dir)
            }
            #if DEBUG
            migrateOldMiniToolsDataGroupFolderToDebugIfNeeded(groupRoot: groupRoot, debugDir: dir)
            #endif
            return dir
        }
        return legacyDirectoryURL
    }

    #if DEBUG
    /// 旧版共用 App Group 下 `MiniToolsData`；Debug 现改用 `MiniToolsData-debug`，首次启动时复制旧目录，避免本地任务“凭空消失”。
    private static func migrateOldMiniToolsDataGroupFolderToDebugIfNeeded(groupRoot: URL, debugDir: URL) {
        let key = "minitools_v2_copied_group_minitoolsdata_to_debug"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let oldShared = groupRoot.appending(path: "MiniToolsData", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: oldShared.path) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        let debugHasAny = fileNames.contains { FileManager.default.fileExists(atPath: debugDir.appending(path: $0).path) }
        if debugHasAny {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        let oldHasAny = fileNames.contains { FileManager.default.fileExists(atPath: oldShared.appending(path: $0).path) }
        guard oldHasAny else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        if !FileManager.default.fileExists(atPath: debugDir.path) {
            try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
        }
        for name in fileNames {
            let src = oldShared.appending(path: name, directoryHint: .notDirectory)
            let dst = debugDir.appending(path: name, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: src.path), !FileManager.default.fileExists(atPath: dst.path) else { continue }
            try? FileManager.default.copyItem(at: src, to: dst)
        }
        UserDefaults.standard.set(true, forKey: key)
    }
    #endif

    /// 首次使用共享目录时，从旧 Application Support 复制已有 JSON。
    private static func migrateFromLegacyIfNeeded(into groupDir: URL) {
        let legacy = legacyDirectoryURL
        var copied = false
        var legacyHadAnyFile = false
        for name in fileNames {
            let dest = groupDir.appending(path: name, directoryHint: .notDirectory)
            let src = legacy.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: src.path) {
                legacyHadAnyFile = true
            }
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            do {
                try FileManager.default.copyItem(at: src, to: dest)
                copied = true
            } catch {
                // 复制失败：不标记「已迁移」，下次启动再试，避免以为已迁完。
            }
        }

        if copied {
            UserDefaults.standard.set(true, forKey: "minitools_migrated_legacy_to_group")
            return
        }
        if !legacyHadAnyFile {
            UserDefaults.standard.set(true, forKey: "minitools_migrated_legacy_to_group")
            return
        }
        let allDestExist = fileNames.allSatisfy { name in
            FileManager.default.fileExists(atPath: groupDir.appending(path: name, directoryHint: .notDirectory).path)
        }
        if allDestExist {
            UserDefaults.standard.set(true, forKey: "minitools_migrated_legacy_to_group")
        }
    }

    private static func url(_ name: String) -> URL {
        directoryURL.appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: - 加载（防静默覆盖）

    /// `shouldWriteBack == false` 时表示磁盘文件存在但解码失败：已通过备份保留，且**不得**用内存中的空数组写回。
    struct ArrayLoadResult<Element> {
        var items: [Element]
        var shouldWriteBack: Bool
    }

    static func loadOneTimeReminders() -> [OneTimeReminder] {
        loadOneTimeRemindersDetailed().items
    }

    static func loadOneTimeRemindersDetailed() -> ArrayLoadResult<OneTimeReminder> {
        loadArrayJson(
            fileName: "one_time_reminders.json",
            decode: { try decoder.decode([OneTimeReminder].self, from: $0) }
        )
    }

    static func loadRecurringTasks() -> [RecurringTask] {
        loadRecurringTasksDetailed().items
    }

    static func loadRecurringTasksDetailed() -> ArrayLoadResult<RecurringTask> {
        loadArrayJson(
            fileName: "recurring_tasks.json",
            decode: { try decoder.decode([RecurringTask].self, from: $0) }
        )
    }

    private static func loadArrayJson<Element>(
        fileName: String,
        decode: (Data) throws -> [Element]
    ) -> ArrayLoadResult<Element> {
        let primary = url(fileName)
        let primaryPath = primary.path
        if !FileManager.default.fileExists(atPath: primaryPath) {
            // 主路径尚无文件时：先读 Application Support 旧版目录，避免误判为空后用 [] 写占位文件、挡住 migrate。
            if let salvaged: [Element] = trySalvageFromLegacy(fileName: fileName, otherThan: primary, decode: decode) {
                return ArrayLoadResult(
                    items: salvaged,
                    shouldWriteBack: !salvaged.isEmpty
                )
            }
            // 确实无任何历史数据：不要在启动流程里写回空文件（首次添加任务时会 save）。
            return ArrayLoadResult(items: [], shouldWriteBack: false)
        }
        do {
            let data = try Data(contentsOf: primary)
            let items = try decode(data)
            // 主包仅有 `[]` 占位时，若旧目录仍有数据则迁回（修复曾误写空数组后的自救）。
            if items.isEmpty,
               let salvaged: [Element] = trySalvageFromLegacy(fileName: fileName, otherThan: primary, decode: decode),
               !salvaged.isEmpty
            {
                let trivialEmpty = (String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) == "[]") ?? false
                if trivialEmpty {
                    return ArrayLoadResult(items: salvaged, shouldWriteBack: true)
                }
            }
            return ArrayLoadResult(items: items, shouldWriteBack: true)
        } catch {
            backupCorrupt(url: primary)
            if let salvaged: [Element] = trySalvageFromLegacy(fileName: fileName, otherThan: primary, decode: decode) {
                return ArrayLoadResult(items: salvaged, shouldWriteBack: true)
            }
            return ArrayLoadResult(items: [], shouldWriteBack: false)
        }
    }

    private static func trySalvageFromLegacy<Element>(
        fileName: String,
        otherThan primary: URL,
        decode: (Data) throws -> [Element]
    ) -> [Element]? {
        let legacyFile = legacyDirectoryURL.appending(path: fileName, directoryHint: .notDirectory)
        guard legacyFile.standardizedFileURL.path != primary.standardizedFileURL.path else { return nil }
        guard FileManager.default.fileExists(atPath: legacyFile.path) else { return nil }
        guard let data = try? Data(contentsOf: legacyFile) else { return nil }
        return try? decode(data)
    }

    private static func backupCorrupt(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        let base = url.deletingPathExtension().lastPathComponent
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingLastPathComponent().appending(path: "\(base).corrupt.\(stamp).json", directoryHint: .notDirectory)
        try? data.write(to: backup, options: [.atomic])
    }

    static func saveOneTimeReminders(_ items: [OneTimeReminder]) {
        save(items, to: url("one_time_reminders.json"))
    }

    static func saveRecurringTasks(_ items: [RecurringTask]) {
        save(items, to: url("recurring_tasks.json"))
    }

    static func loadHourlyWindowTasksDetailed() -> ArrayLoadResult<HourlyWindowTask> {
        loadArrayJson(
            fileName: "hourly_window_tasks.json",
            decode: { try decoder.decode([HourlyWindowTask].self, from: $0) }
        )
    }

    static func saveHourlyWindowTasks(_ items: [HourlyWindowTask]) {
        save(items, to: url("hourly_window_tasks.json"))
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            AppLog.store.error("JSON save failed at \(url.path): \(error.localizedDescription)")
        }
    }
}
