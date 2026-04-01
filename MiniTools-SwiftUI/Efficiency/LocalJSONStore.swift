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
            /// Xcode Debug 曾写入 `MiniToolsData-debug`，与安装版/小组件读的 `MiniToolsData` 分离；迁回避免「代码里看得到、桌面打开是空的」。
            consolidateFormerDebugSubfolderIntoCanonical(groupRoot: groupRoot, canonicalDir: dir)
            /// 小组件只能读 App Group，读不到主应用 Application Support；若此处曾是占位 `[]` 而 Support 里仍有数据，必须拷回。
            repairGroupJSONPlaceholdersFromLegacyIfNeeded(groupDir: dir)
            return dir
        }
        return legacyDirectoryURL
    }

    /// 每进程最多合并一次；避免依赖「仅首次启动」标志导致漏迁。
    private static var didConsolidateFormerDebugSubfolder = false

    /// 将历史目录 `MiniToolsData-debug` 中的非空 JSON 合并进 canonical（仅当对应 canonical 文件缺失或为字面量 `[]` 时复制）。
    private static func consolidateFormerDebugSubfolderIntoCanonical(groupRoot: URL, canonicalDir: URL) {
        guard !didConsolidateFormerDebugSubfolder else { return }
        didConsolidateFormerDebugSubfolder = true

        let debugDir = groupRoot.appending(path: "MiniToolsData-debug", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: debugDir.path) else { return }

        if !FileManager.default.fileExists(atPath: canonicalDir.path) {
            try? FileManager.default.createDirectory(at: canonicalDir, withIntermediateDirectories: true)
        }
        for name in fileNames {
            let cURL = canonicalDir.appending(path: name, directoryHint: .notDirectory)
            let dURL = debugDir.appending(path: name, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: dURL.path) else { continue }
            guard let debugData = try? Data(contentsOf: dURL), !debugData.isEmpty else { continue }
            guard !isJSONArrayOnDiskEmpty(debugData) else { continue }

            let canonExists = FileManager.default.fileExists(atPath: cURL.path)
            let canonData = canonExists ? (try? Data(contentsOf: cURL)) ?? Data() : Data()
            let canonEmpty = !canonExists || canonData.isEmpty || isJSONArrayOnDiskEmpty(canonData)
            if canonEmpty {
                try? debugData.write(to: cURL, options: .atomic)
            }
        }
    }

    private static func isJSONArrayOnDiskEmpty(_ data: Data) -> Bool {
        guard let s = String(data: data, encoding: .utf8) else { return true }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "[]"
    }

    /// 每进程一次：把 Application Support 里的非空 JSON 写回 Group（当 Group 内缺失或仅为 `[]`）。小组件扩展看不到主应用容器下的 Support。
    private static var didRepairGroupPlaceholdersFromLegacy = false

    private static func repairGroupJSONPlaceholdersFromLegacyIfNeeded(groupDir: URL) {
        guard !didRepairGroupPlaceholdersFromLegacy else { return }
        didRepairGroupPlaceholdersFromLegacy = true
        let legacy = legacyDirectoryURL
        var wrote = false
        for name in fileNames {
            let dest = groupDir.appending(path: name, directoryHint: .notDirectory)
            let src = legacy.appending(path: name, directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            guard let srcData = try? Data(contentsOf: src), !isJSONArrayOnDiskEmpty(srcData) else { continue }
            let destNeedsRepair: Bool
            if !FileManager.default.fileExists(atPath: dest.path) {
                destNeedsRepair = true
            } else if let d = try? Data(contentsOf: dest), isJSONArrayOnDiskEmpty(d) {
                destNeedsRepair = true
            } else {
                destNeedsRepair = false
            }
            guard destNeedsRepair else { continue }
            try? srcData.write(to: dest, options: .atomic)
            wrote = true
        }
        if wrote {
            AppLog.store.debug("已从 Application Support 补写 App Group JSON（消除小组件与主应用数据源不一致）")
            DispatchQueue.main.async {
                MiniToolsWidgetReloader.reloadAll()
            }
        }
    }

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
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            guard let srcData = try? Data(contentsOf: src), !isJSONArrayOnDiskEmpty(srcData) else { continue }
            let needCopy: Bool
            if !FileManager.default.fileExists(atPath: dest.path) {
                needCopy = true
            } else if let d = try? Data(contentsOf: dest), isJSONArrayOnDiskEmpty(d) {
                needCopy = true
            } else {
                needCopy = false
            }
            guard needCopy else { continue }
            do {
                try srcData.write(to: dest, options: .atomic)
                copied = true
            } catch {
                // 写入失败：不标记「已迁移」，下次启动再试。
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
