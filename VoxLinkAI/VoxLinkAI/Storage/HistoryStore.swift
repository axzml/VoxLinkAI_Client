//
//  HistoryStore.swift
//  VoxLink
//
//  历史记录存储 - SQLite（与 Python 端共享）
//

import Combine
import Foundation
import SQLite3

/// 历史记录项
struct HistoryItem: Identifiable {
    let id: Int64
    let text: String              // transcript
    let polished: String?
    let finalOutput: String?
    let createdAt: Date
    var isFavorite: Bool

    /// 用于显示的文本（优先润色结果）
    var displayText: String {
        polished ?? text
    }
}

/// 历史记录存储（SQLite）
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbPath: String
    @Published private(set) var items: [HistoryItem] = []

    // 不再限制历史记录数量，SQLite 可以存储大量数据
    // 文本数据占用空间很小，用户可自行清理不需要的记录

    // MARK: - Initialization

    private init() {
        // 数据库路径：~/.voxlinkai/history.db（与 Python 端共享）
        let voxlinkDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voxlinkai", isDirectory: true).path

        // 确保目录存在
        try? FileManager.default.createDirectory(atPath: voxlinkDir, withIntermediateDirectories: true)

        self.dbPath = (voxlinkDir as NSString).appendingPathComponent("history.db")

        // 打开数据库
        openDatabase()

        // 加载历史记录
        load()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Operations

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[HistoryStore] Failed to open database: \(dbPath)")
            return
        }

        // 创建表（如果不存在）
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                transcript TEXT NOT NULL,
                polished TEXT,
                intent TEXT,
                ai_result TEXT,
                final_output TEXT NOT NULL,
                processing_time_ms INTEGER,
                success INTEGER NOT NULL DEFAULT 1,
                is_favorite INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_history_created_at ON history(created_at);
            CREATE INDEX IF NOT EXISTS idx_history_is_favorite ON history(is_favorite);
            """

        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            print("[HistoryStore] Failed to create table")
        }

        // 添加 is_favorite 列（如果不存在，兼容旧数据库）
        let addColumnSQL = "ALTER TABLE history ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0"
        sqlite3_exec(db, addColumnSQL, nil, nil, nil)  // 忽略错误（列可能已存在）

        print("[HistoryStore] Database opened: \(dbPath)")
    }

    // MARK: - Public Methods

    /// 添加历史记录
    func add(text: String, polished: String?) {
        // 使用与 Python 兼容的时间格式
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.string(from: Date())
        let finalOutput = polished ?? text

        let insertSQL = """
            INSERT INTO history (created_at, transcript, polished, final_output, success)
            VALUES (?, ?, ?, ?, 1)
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (createdAt as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (text as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, polished.flatMap { ($0 as NSString).utf8String }, -1, nil)
            sqlite3_bind_text(statement, 4, (finalOutput as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_DONE {
                print("[HistoryStore] Added record with id: \(sqlite3_last_insert_rowid(db))")
            }
        }

        sqlite3_finalize(statement)

        // 清理旧记录
        cleanupOldRecords()

        // 重新加载
        load()
    }

    /// 删除历史记录
    func delete(id: Int64) {
        let deleteSQL = "DELETE FROM history WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)
        load()
    }

    /// 清空所有历史记录
    func clearAll() {
        let deleteAllSQL = "DELETE FROM history"
        sqlite3_exec(db, deleteAllSQL, nil, nil, nil)
        load()
    }

    /// 搜索历史记录
    func search(query: String) -> [HistoryItem] {
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.text.localizedCaseInsensitiveContains(query) ||
            (item.polished?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// 切换收藏状态
    func toggleFavorite(id: Int64) {
        let updateSQL = "UPDATE history SET is_favorite = NOT is_favorite WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)
        load()
    }

    /// 获取收藏的记录
    func getFavorites() -> [HistoryItem] {
        items.filter { $0.isFavorite }
    }

    /// 获取收藏数量
    var favoriteCount: Int {
        items.filter { $0.isFavorite }.count
    }

    /// 获取最近的历史记录
    func getRecent(limit: Int = 50) -> [HistoryItem] {
        Array(items.prefix(limit))
    }

    // MARK: - Private Methods

    private func load() {
        var newItems: [HistoryItem] = []

        // 不再限制加载数量，加载所有历史记录
        let selectSQL = """
            SELECT id, created_at, transcript, polished, final_output, is_favorite
            FROM history
            ORDER BY created_at DESC
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {

            // 日期格式化器 - 支持多种格式
            let iso8601WithFractional = ISO8601DateFormatter()
            iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let iso8601Basic = ISO8601DateFormatter()
            iso8601Basic.formatOptions = [.withInternetDateTime]

            // Python 格式：2026-02-16T00:35:52.599988（无时区后缀）
            let pythonFormatter = DateFormatter()
            pythonFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            pythonFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")

            // Python 格式（无微秒）
            let pythonFormatterNoMicro = DateFormatter()
            pythonFormatterNoMicro.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            pythonFormatterNoMicro.timeZone = TimeZone(identifier: "Asia/Shanghai")

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let createdAtString = String(cString: sqlite3_column_text(statement, 1))
                let transcript = String(cString: sqlite3_column_text(statement, 2))
                let polished = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let finalOutput = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                let isFavorite = sqlite3_column_int(statement, 5) == 1

                // 尝试多种格式解析
                let createdAt = iso8601WithFractional.date(from: createdAtString)
                    ?? iso8601Basic.date(from: createdAtString)
                    ?? pythonFormatter.date(from: createdAtString)
                    ?? pythonFormatterNoMicro.date(from: createdAtString)
                    ?? Date()

                let item = HistoryItem(
                    id: id,
                    text: transcript,
                    polished: polished,
                    finalOutput: finalOutput,
                    createdAt: createdAt,
                    isFavorite: isFavorite
                )

                newItems.append(item)
            }
        }

        sqlite3_finalize(statement)
        items = newItems
        print("[HistoryStore] Loaded \(items.count) items from database")
    }

    private func cleanupOldRecords() {
        // 不再自动清理旧记录
        // 用户可以通过删除功能手动清理不需要的记录
    }
}
