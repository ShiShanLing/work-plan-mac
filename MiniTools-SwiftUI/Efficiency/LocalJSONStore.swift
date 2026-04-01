//
//  LocalJSONStore.swift
//  MiniTools-SwiftUI
//

import Foundation

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
        if !FileManager.default.fileExists(atPath: dir.path()) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var directoryURL: URL {
        if let groupRoot = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) {
            let dir = groupRoot.appending(path: "MiniToolsData", directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: dir.path()) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                migrateFromLegacyIfNeeded(into: dir)
            } else if !UserDefaults.standard.bool(forKey: "minitools_migrated_legacy_to_group") {
                migrateFromLegacyIfNeeded(into: dir)
            }
            return dir
        }
        return legacyDirectoryURL
    }

    /// 首次使用共享目录时，从旧 Application Support 复制已有 JSON。
    private static func migrateFromLegacyIfNeeded(into groupDir: URL) {
        let legacy = legacyDirectoryURL
        var copied = false
        var legacyHadAnyFile = false
        for name in fileNames {
            let dest = groupDir.appending(path: name, directoryHint: .notDirectory)
            let src = legacy.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: src.path()) {
                legacyHadAnyFile = true
            }
            guard !FileManager.default.fileExists(atPath: dest.path()) else { continue }
            guard FileManager.default.fileExists(atPath: src.path()) else { continue }
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
            FileManager.default.fileExists(atPath: groupDir.appending(path: name, directoryHint: .notDirectory).path())
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
        if !FileManager.default.fileExists(atPath: primary.path()) {
            return ArrayLoadResult(items: [], shouldWriteBack: true)
        }
        do {
            let data = try Data(contentsOf: primary)
            let items = try decode(data)
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
        guard FileManager.default.fileExists(atPath: legacyFile.path()) else { return nil }
        guard let data = try? Data(contentsOf: legacyFile) else { return nil }
        return try? decode(data)
    }

    private static func backupCorrupt(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
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
        } catch {}
    }
}
