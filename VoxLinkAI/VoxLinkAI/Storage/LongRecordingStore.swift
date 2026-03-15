//
//  LongRecordingStore.swift
//  VoxLink
//
//  持续录音存储 - SQLite
//

import Combine
import Foundation
import SQLite3

// MARK: - Models

/// 持续录音会话
struct LongRecordingSession: Identifiable {
    let id: Int64
    var title: String?
    let startTime: Date
    var endTime: Date?
    var totalDuration: TimeInterval  // 秒
    var status: LongRecordingStatus
    var previewText: String?
    var isFavorite: Bool

    /// 格式化的时长字符串
    var durationString: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) % 3600 / 60
        let seconds = Int(totalDuration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// 显示标题（优先用户自定义，否则使用时间）
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: startTime)
    }
}

/// 录音状态
enum LongRecordingStatus: String {
    case recording = "recording"
    case paused = "paused"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .recording: return "录音中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        }
    }
}

/// 语音片段
struct VoiceSegment: Identifiable {
    let id: Int64
    let sessionId: Int64
    var startOffset: TimeInterval  // 毫秒，相对于会话开始
    var endOffset: TimeInterval
    var transcript: String?
    let createdAt: Date

    /// 片段时长（秒）
    var duration: TimeInterval {
        (endOffset - startOffset) / 1000.0
    }

    /// 格式化的开始时间
    var startTimeString: String {
        let totalSeconds = Int(startOffset / 1000.0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// 思维段（聚合多个语音片段）
struct ThoughtSegment: Identifiable {
    let id: Int64
    let sessionId: Int64
    var startOffset: TimeInterval  // 毫秒，相对于会话开始
    var endOffset: TimeInterval
    var rawTranscript: String      // 原始转录文本（多个语音片段合并）
    var polishedTranscript: String? // AI 润色后的文本
    var isPolished: Bool           // 是否已润色
    var position: Int              // 在时间轴上的位置（用于左右交替布局）
    let createdAt: Date
    var polishedAt: Date?

    /// 片段时长（秒）
    var duration: TimeInterval {
        (endOffset - startOffset) / 1000.0
    }

    /// 格式化的开始时间
    var startTimeString: String {
        let totalSeconds = Int(startOffset / 1000.0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 显示文本（优先润色版，否则原始版）
    var displayText: String {
        polishedTranscript ?? rawTranscript
    }

    /// 是否在左侧显示（根据 position 判断）
    var isOnLeft: Bool {
        position % 2 == 0
    }
}

// MARK: - Long Recording Store

/// 持续录音存储
@MainActor
final class LongRecordingStore: ObservableObject {
    static let shared = LongRecordingStore()

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbPath: String

    @Published private(set) var sessions: [LongRecordingSession] = []
    @Published private(set) var currentSession: LongRecordingSession?
    @Published private(set) var currentSegments: [VoiceSegment] = []
    @Published private(set) var currentThoughtSegments: [ThoughtSegment] = []

    // MARK: - Initialization

    private init() {
        // 数据库路径：~/.voxlinkai/long_recording.db
        let voxlinkDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".voxlinkai", isDirectory: true).path

        // 确保目录存在
        try? FileManager.default.createDirectory(atPath: voxlinkDir, withIntermediateDirectories: true)

        self.dbPath = (voxlinkDir as NSString).appendingPathComponent("long_recording.db")

        // 打开数据库
        openDatabase()

        // 加载历史记录
        loadSessions()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Operations

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("[LongRecordingStore] Failed to open database: \(dbPath)")
            return
        }

        // 创建会话表
        let createSessionsTable = """
            CREATE TABLE IF NOT EXISTS long_recording_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT,
                total_duration REAL DEFAULT 0,
                status TEXT DEFAULT 'recording',
                preview_text TEXT,
                is_favorite INTEGER DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_sessions_start_time ON long_recording_sessions(start_time);
            CREATE INDEX IF NOT EXISTS idx_sessions_status ON long_recording_sessions(status);
            """

        // 迁移：添加 is_favorite 列（如果不存在）
        // 先检查列是否存在
        var columnExists = false
        let checkColumnSQL = "PRAGMA table_info(long_recording_sessions)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkColumnSQL, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let columnName = sqlite3_column_text(stmt, 1) {
                    if String(cString: columnName) == "is_favorite" {
                        columnExists = true
                        break
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        if !columnExists {
            let addFavoriteColumn = "ALTER TABLE long_recording_sessions ADD COLUMN is_favorite INTEGER DEFAULT 0"
            if sqlite3_exec(db, addFavoriteColumn, nil, nil, nil) != SQLITE_OK {
                print("[LongRecordingStore] Warning: Failed to add is_favorite column")
            }
        }

        // 创建片段表
        let createSegmentsTable = """
            CREATE TABLE IF NOT EXISTS voice_segments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                start_offset REAL NOT NULL,
                end_offset REAL NOT NULL,
                transcript TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (session_id) REFERENCES long_recording_sessions(id)
            );
            CREATE INDEX IF NOT EXISTS idx_segments_session ON voice_segments(session_id);
            """

        // 创建思维段表
        let createThoughtSegmentsTable = """
            CREATE TABLE IF NOT EXISTS thought_segments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                start_offset REAL NOT NULL,
                end_offset REAL NOT NULL,
                raw_transcript TEXT NOT NULL,
                polished_transcript TEXT,
                is_polished INTEGER DEFAULT 0,
                position INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                polished_at TEXT,
                FOREIGN KEY (session_id) REFERENCES long_recording_sessions(id)
            );
            CREATE INDEX IF NOT EXISTS idx_thought_segments_session ON thought_segments(session_id);
            """

        if sqlite3_exec(db, createSessionsTable, nil, nil, nil) != SQLITE_OK {
            print("[LongRecordingStore] Failed to create sessions table")
        }

        if sqlite3_exec(db, createSegmentsTable, nil, nil, nil) != SQLITE_OK {
            print("[LongRecordingStore] Failed to create segments table")
        }

        if sqlite3_exec(db, createThoughtSegmentsTable, nil, nil, nil) != SQLITE_OK {
            print("[LongRecordingStore] Failed to create thought_segments table")
        }

        print("[LongRecordingStore] Database opened: \(dbPath)")
    }

    // MARK: - Session Operations

    /// 创建新会话
    @discardableResult
    func createSession() -> LongRecordingSession? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startTime = formatter.string(from: Date())

        let insertSQL = """
            INSERT INTO long_recording_sessions (start_time, status)
            VALUES (?, 'recording')
            """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            print("[LongRecordingStore] Failed to prepare insert statement")
            return nil
        }

        sqlite3_bind_text(statement, 1, (startTime as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            sqlite3_finalize(statement)
            print("[LongRecordingStore] Failed to insert session")
            return nil
        }

        sqlite3_finalize(statement)

        let sessionId = sqlite3_last_insert_rowid(db)
        print("[LongRecordingStore] Created session with id: \(sessionId)")

        // 创建会话对象
        let session = LongRecordingSession(
            id: sessionId,
            title: nil,
            startTime: Date(),
            endTime: nil,
            totalDuration: 0,
            status: .recording,
            previewText: nil,
            isFavorite: false
        )

        currentSession = session
        currentSegments = []
        currentThoughtSegments = []  // 清空思维段列表，避免显示之前历史记录的内容

        return session
    }

    /// 更新会话状态
    func updateSessionStatus(_ sessionId: Int64, status: LongRecordingStatus) {
        let updateSQL = "UPDATE long_recording_sessions SET status = ? WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, sessionId)
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)

        // 更新当前会话
        if currentSession?.id == sessionId {
            currentSession = LongRecordingSession(
                id: sessionId,
                title: currentSession?.title,
                startTime: currentSession?.startTime ?? Date(),
                endTime: currentSession?.endTime,
                totalDuration: currentSession?.totalDuration ?? 0,
                status: status,
                previewText: currentSession?.previewText,
                isFavorite: currentSession?.isFavorite ?? false
            )
        }

        print("[LongRecordingStore] Updated session \(sessionId) status to \(status.rawValue)")
    }

    /// 更新会话标题
    func updateSessionTitle(_ sessionId: Int64, title: String) {
        let updateSQL = "UPDATE long_recording_sessions SET title = ? WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, sessionId)
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)

        // 更新当前会话
        if currentSession?.id == sessionId {
            currentSession = LongRecordingSession(
                id: sessionId,
                title: title,
                startTime: currentSession?.startTime ?? Date(),
                endTime: currentSession?.endTime,
                totalDuration: currentSession?.totalDuration ?? 0,
                status: currentSession?.status ?? .recording,
                previewText: currentSession?.previewText,
                isFavorite: currentSession?.isFavorite ?? false
            )
        }

        loadSessions()
    }

    /// 完成会话
    func completeSession(_ sessionId: Int64) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let endTime = formatter.string(from: Date())

        // 计算总时长
        let totalDuration = calculateSessionDuration(sessionId)

        let updateSQL = """
            UPDATE long_recording_sessions
            SET status = 'completed', end_time = ?, total_duration = ?
            WHERE id = ?
            """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (endTime as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 2, totalDuration)
            sqlite3_bind_int64(statement, 3, sessionId)
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)

        // 更新预览文本
        updateSessionPreview(sessionId)

        // 注意：不清空 currentSession、currentSegments、currentThoughtSegments
        // 这样用户停止录音后可以继续在时光轴上查看结果
        // 只有在开始新录音（createSession）或用户离开持续录音页面时才清空

        // 重新加载列表
        loadSessions()

        print("[LongRecordingStore] Completed session \(sessionId), duration: \(totalDuration)s")
    }

    /// 删除会话
    func deleteSession(_ sessionId: Int64) {
        // 先删除关联的思维段
        let deleteThoughtSegmentsSQL = "DELETE FROM thought_segments WHERE session_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteThoughtSegmentsSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // 删除关联的语音片段
        let deleteSegmentsSQL = "DELETE FROM voice_segments WHERE session_id = ?"
        if sqlite3_prepare_v2(db, deleteSegmentsSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // 删除会话
        let deleteSessionSQL = "DELETE FROM long_recording_sessions WHERE id = ?"
        if sqlite3_prepare_v2(db, deleteSessionSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        loadSessions()
        print("[LongRecordingStore] Deleted session \(sessionId)")
    }

    /// 切换会话收藏状态
    func toggleFavorite(_ sessionId: Int64) {
        // 先获取当前状态
        let selectSQL = "SELECT is_favorite FROM long_recording_sessions WHERE id = ?"
        var statement: OpaquePointer?
        var currentFavorite = false

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            if sqlite3_step(statement) == SQLITE_ROW {
                currentFavorite = sqlite3_column_int(statement, 0) == 1
            }
        }
        sqlite3_finalize(statement)

        // 切换状态
        let newFavorite = !currentFavorite
        let updateSQL = "UPDATE long_recording_sessions SET is_favorite = ? WHERE id = ?"
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, newFavorite ? 1 : 0)
            sqlite3_bind_int64(statement, 2, sessionId)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // 更新当前会话
        if currentSession?.id == sessionId {
            currentSession = LongRecordingSession(
                id: sessionId,
                title: currentSession?.title,
                startTime: currentSession?.startTime ?? Date(),
                endTime: currentSession?.endTime,
                totalDuration: currentSession?.totalDuration ?? 0,
                status: currentSession?.status ?? .recording,
                previewText: currentSession?.previewText,
                isFavorite: newFavorite
            )
        }

        loadSessions()
        print("[LongRecordingStore] Toggled favorite for session \(sessionId) to \(newFavorite)")
    }

    /// 加载会话列表
    func loadSessions() {
        var newSessions: [LongRecordingSession] = []

        let selectSQL = """
            SELECT id, title, start_time, end_time, total_duration, status, preview_text, is_favorite
            FROM long_recording_sessions
            ORDER BY start_time DESC
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let title = sqlite3_column_text(statement, 1).map { String(cString: $0) }
                let startTimeString = String(cString: sqlite3_column_text(statement, 2))
                let endTimeString = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let totalDuration = sqlite3_column_double(statement, 4)
                let statusString = String(cString: sqlite3_column_text(statement, 5))
                let previewText = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let isFavorite = sqlite3_column_int(statement, 7) == 1

                let startTime = parseDate(startTimeString) ?? Date()
                let endTime = endTimeString.flatMap { parseDate($0) }
                let status = LongRecordingStatus(rawValue: statusString) ?? .completed

                let session = LongRecordingSession(
                    id: id,
                    title: title,
                    startTime: startTime,
                    endTime: endTime,
                    totalDuration: totalDuration,
                    status: status,
                    previewText: previewText,
                    isFavorite: isFavorite
                )

                newSessions.append(session)
            }
        }

        sqlite3_finalize(statement)
        sessions = newSessions
        print("[LongRecordingStore] Loaded \(sessions.count) sessions")
    }

    /// 设置当前查看的会话（用于时光轴展示）
    func setCurrentViewingSession(_ session: LongRecordingSession?) {
        guard let session = session else {
            currentSegments = []
            currentThoughtSegments = []
            return
        }

        loadSegments(for: session.id)
        loadThoughtSegments(for: session.id)
    }

    /// 清空当前查看状态（用于离开持续录音页面时重置）
    func clearCurrentViewingState() {
        currentSession = nil
        currentSegments = []
        currentThoughtSegments = []
    }

    /// 获取所有收藏的会话
    func getFavoriteSessions() -> [LongRecordingSession] {
        return sessions.filter { $0.isFavorite }
    }

    /// 重命名会话
    func renameSession(_ sessionId: Int64, newTitle: String) {
        let updateSQL = "UPDATE long_recording_sessions SET title = ? WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (newTitle as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, sessionId)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // 更新当前会话
        if currentSession?.id == sessionId {
            currentSession = LongRecordingSession(
                id: sessionId,
                title: newTitle,
                startTime: currentSession?.startTime ?? Date(),
                endTime: currentSession?.endTime,
                totalDuration: currentSession?.totalDuration ?? 0,
                status: currentSession?.status ?? .completed,
                previewText: currentSession?.previewText,
                isFavorite: currentSession?.isFavorite ?? false
            )
        }

        loadSessions()
        print("[LongRecordingStore] Renamed session \(sessionId) to: \(newTitle)")
    }

    /// 获取会话的所有思维段文本（用于复制全文）
    /// - Parameter sessionId: 会话 ID
    /// - Returns: 所有思维段的文本，用空行分隔
    func getAllThoughtSegmentsText(for sessionId: Int64) -> String {
        // 加载该会话的思维段
        var segments: [ThoughtSegment] = []
        let selectSQL = """
            SELECT id, session_id, start_offset, end_offset, raw_transcript, polished_transcript, is_polished, position, created_at, polished_at
            FROM thought_segments
            WHERE session_id = ?
            ORDER BY position ASC
            """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let sessionId = sqlite3_column_int64(statement, 1)
                let startOffset = sqlite3_column_double(statement, 2)
                let endOffset = sqlite3_column_double(statement, 3)
                let rawTranscript = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let polishedTranscript = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let isPolished = sqlite3_column_int(statement, 6) == 1
                let position = sqlite3_column_int(statement, 7)
                let createdAtString = sqlite3_column_text(statement, 8).map { String(cString: $0) } ?? ""
                let polishedAt = sqlite3_column_text(statement, 9).map { String(cString: $0) }

                let createdAt = parseDate(createdAtString) ?? Date()

                let segment = ThoughtSegment(
                    id: id,
                    sessionId: sessionId,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    rawTranscript: rawTranscript,
                    polishedTranscript: polishedTranscript,
                    isPolished: isPolished,
                    position: Int(position),
                    createdAt: createdAt,
                    polishedAt: polishedAt.flatMap { parseDate($0) }
                )
                segments.append(segment)
            }
        }
        sqlite3_finalize(statement)

        // 拼接文本（优先使用润色后的文本）
        let texts = segments.map { $0.displayText }
        return texts.joined(separator: "\n\n")
    }

    // MARK: - Segment Operations

    /// 添加语音片段
    @discardableResult
    func addSegment(sessionId: Int64, startOffset: TimeInterval, endOffset: TimeInterval, transcript: String?) -> VoiceSegment? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.string(from: Date())

        let insertSQL = """
            INSERT INTO voice_segments (session_id, start_offset, end_offset, transcript, created_at)
            VALUES (?, ?, ?, ?, ?)
            """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            print("[LongRecordingStore] Failed to prepare segment insert")
            return nil
        }

        sqlite3_bind_int64(statement, 1, sessionId)
        sqlite3_bind_double(statement, 2, startOffset)
        sqlite3_bind_double(statement, 3, endOffset)
        sqlite3_bind_text(statement, 4, transcript.flatMap { ($0 as NSString).utf8String }, -1, nil)
        sqlite3_bind_text(statement, 5, (createdAt as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            sqlite3_finalize(statement)
            print("[LongRecordingStore] Failed to insert segment")
            return nil
        }

        sqlite3_finalize(statement)

        let segmentId = sqlite3_last_insert_rowid(db)
        print("[LongRecordingStore] Added segment \(segmentId) to session \(sessionId)")

        let segment = VoiceSegment(
            id: segmentId,
            sessionId: sessionId,
            startOffset: startOffset,
            endOffset: endOffset,
            transcript: transcript,
            createdAt: Date()
        )

        // 如果是当前会话，更新片段列表
        if currentSession?.id == sessionId {
            currentSegments.append(segment)
        }

        // 更新预览文本（使用第一个片段的转录）
        updateSessionPreview(sessionId)

        return segment
    }

    /// 更新片段转录文本
    func updateSegmentTranscript(_ segmentId: Int64, transcript: String) {
        let updateSQL = "UPDATE voice_segments SET transcript = ? WHERE id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (transcript as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 2, segmentId)
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)

        // 更新当前片段列表
        if let index = currentSegments.firstIndex(where: { $0.id == segmentId }) {
            currentSegments[index] = VoiceSegment(
                id: segmentId,
                sessionId: currentSegments[index].sessionId,
                startOffset: currentSegments[index].startOffset,
                endOffset: currentSegments[index].endOffset,
                transcript: transcript,
                createdAt: currentSegments[index].createdAt
            )
        }
    }

    /// 加载会话的所有片段
    func loadSegments(for sessionId: Int64) {
        var segments: [VoiceSegment] = []

        let selectSQL = """
            SELECT id, session_id, start_offset, end_offset, transcript, created_at
            FROM voice_segments
            WHERE session_id = ?
            ORDER BY start_offset ASC
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let sessionId = sqlite3_column_int64(statement, 1)
                let startOffset = sqlite3_column_double(statement, 2)
                let endOffset = sqlite3_column_double(statement, 3)
                let transcript = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                let createdAtString = String(cString: sqlite3_column_text(statement, 5))

                let segment = VoiceSegment(
                    id: id,
                    sessionId: sessionId,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    transcript: transcript,
                    createdAt: parseDate(createdAtString) ?? Date()
                )

                segments.append(segment)
            }
        }

        sqlite3_finalize(statement)
        currentSegments = segments
        print("[LongRecordingStore] Loaded \(segments.count) segments for session \(sessionId)")
    }

    /// 获取会话的片段数量
    func getSegmentCount(for sessionId: Int64) -> Int {
        let selectSQL = "SELECT COUNT(*) FROM voice_segments WHERE session_id = ?"
        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }

        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Helper Methods

    private func parseDate(_ string: String) -> Date? {
        let iso8601WithFractional = ISO8601DateFormatter()
        iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso8601Basic = ISO8601DateFormatter()
        iso8601Basic.formatOptions = [.withInternetDateTime]

        return iso8601WithFractional.date(from: string)
            ?? iso8601Basic.date(from: string)
    }

    private func calculateSessionDuration(_ sessionId: Int64) -> TimeInterval {
        let selectSQL = """
            SELECT MAX(end_offset) - MIN(start_offset)
            FROM voice_segments
            WHERE session_id = ?
            """
        var statement: OpaquePointer?
        var duration: TimeInterval = 0

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            if sqlite3_step(statement) == SQLITE_ROW {
                duration = sqlite3_column_double(statement, 0) / 1000.0  // 转换为秒
            }
        }

        sqlite3_finalize(statement)
        return duration
    }

    private func updateSessionPreview(_ sessionId: Int64) {
        // 获取第一个有转录内容的片段
        let selectSQL = """
            SELECT transcript FROM voice_segments
            WHERE session_id = ? AND transcript IS NOT NULL AND transcript != ''
            ORDER BY start_offset ASC
            LIMIT 1
            """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            if sqlite3_step(statement) == SQLITE_ROW {
                if let transcript = sqlite3_column_text(statement, 0) {
                    let text = String(cString: transcript)
                    // 截取前50个字符作为预览
                    let preview = text.count > 50 ? String(text.prefix(50)) + "..." : text

                    let updateSQL = "UPDATE long_recording_sessions SET preview_text = ? WHERE id = ?"
                    var updateStatement: OpaquePointer?

                    if sqlite3_prepare_v2(db, updateSQL, -1, &updateStatement, nil) == SQLITE_OK {
                        sqlite3_bind_text(updateStatement, 1, (preview as NSString).utf8String, -1, nil)
                        sqlite3_bind_int64(updateStatement, 2, sessionId)
                        sqlite3_step(updateStatement)
                    }
                    sqlite3_finalize(updateStatement)

                    // 更新当前会话
                    if currentSession?.id == sessionId {
                        currentSession = LongRecordingSession(
                            id: sessionId,
                            title: currentSession?.title,
                            startTime: currentSession?.startTime ?? Date(),
                            endTime: currentSession?.endTime,
                            totalDuration: currentSession?.totalDuration ?? 0,
                            status: currentSession?.status ?? .recording,
                            previewText: preview,
                            isFavorite: currentSession?.isFavorite ?? false
                        )
                    }
                }
            }
        }

        sqlite3_finalize(statement)
    }

    // MARK: - Thought Segment Operations

    /// 添加思维段
    @discardableResult
    func addThoughtSegment(sessionId: Int64, startOffset: TimeInterval, endOffset: TimeInterval, rawTranscript: String, position: Int) -> ThoughtSegment? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.string(from: Date())

        let insertSQL = """
            INSERT INTO thought_segments (session_id, start_offset, end_offset, raw_transcript, is_polished, position, created_at)
            VALUES (?, ?, ?, ?, 0, ?, ?)
            """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            print("[LongRecordingStore] Failed to prepare thought segment insert")
            return nil
        }

        sqlite3_bind_int64(statement, 1, sessionId)
        sqlite3_bind_double(statement, 2, startOffset)
        sqlite3_bind_double(statement, 3, endOffset)
        sqlite3_bind_text(statement, 4, (rawTranscript as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(position))
        sqlite3_bind_text(statement, 6, (createdAt as NSString).utf8String, -1, nil)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            sqlite3_finalize(statement)
            print("[LongRecordingStore] Failed to insert thought segment")
            return nil
        }

        sqlite3_finalize(statement)

        let segmentId = sqlite3_last_insert_rowid(db)
        print("[LongRecordingStore] Added thought segment \(segmentId) to session \(sessionId)")

        let segment = ThoughtSegment(
            id: segmentId,
            sessionId: sessionId,
            startOffset: startOffset,
            endOffset: endOffset,
            rawTranscript: rawTranscript,
            polishedTranscript: nil,
            isPolished: false,
            position: position,
            createdAt: Date(),
            polishedAt: nil
        )

        // 如果是当前会话，更新思维段列表
        if currentSession?.id == sessionId {
            currentThoughtSegments.append(segment)
        }

        return segment
    }

    /// 更新思维段的润色文本
    func updateThoughtSegmentPolished(_ segmentId: Int64, polishedTranscript: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let polishedAt = formatter.string(from: Date())

        let updateSQL = """
            UPDATE thought_segments
            SET polished_transcript = ?, is_polished = 1, polished_at = ?
            WHERE id = ?
            """
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (polishedTranscript as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (polishedAt as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 3, segmentId)
            sqlite3_step(statement)
        }

        sqlite3_finalize(statement)

        // 更新当前思维段列表
        if let index = currentThoughtSegments.firstIndex(where: { $0.id == segmentId }) {
            currentThoughtSegments[index] = ThoughtSegment(
                id: segmentId,
                sessionId: currentThoughtSegments[index].sessionId,
                startOffset: currentThoughtSegments[index].startOffset,
                endOffset: currentThoughtSegments[index].endOffset,
                rawTranscript: currentThoughtSegments[index].rawTranscript,
                polishedTranscript: polishedTranscript,
                isPolished: true,
                position: currentThoughtSegments[index].position,
                createdAt: currentThoughtSegments[index].createdAt,
                polishedAt: Date()
            )
        }

        print("[LongRecordingStore] Updated thought segment \(segmentId) with polished text")
    }

    /// 更新思维段的原始转录（用于追加新的语音段）
    func appendThoughtSegmentRaw(_ segmentId: Int64, additionalTranscript: String, newEndOffset: TimeInterval) {
        // 先获取当前的原始转录
        let selectSQL = "SELECT raw_transcript FROM thought_segments WHERE id = ?"
        var statement: OpaquePointer?
        var currentRaw = ""

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, segmentId)
            if sqlite3_step(statement) == SQLITE_ROW {
                if let raw = sqlite3_column_text(statement, 0) {
                    currentRaw = String(cString: raw)
                }
            }
        }
        sqlite3_finalize(statement)

        // 合并转录文本
        let newRaw = currentRaw.isEmpty ? additionalTranscript : currentRaw + " " + additionalTranscript

        // 更新数据库
        let updateSQL = """
            UPDATE thought_segments
            SET raw_transcript = ?, end_offset = ?
            WHERE id = ?
            """
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (newRaw as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 2, newEndOffset)
            sqlite3_bind_int64(statement, 3, segmentId)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)

        // 更新当前思维段列表
        if let index = currentThoughtSegments.firstIndex(where: { $0.id == segmentId }) {
            currentThoughtSegments[index] = ThoughtSegment(
                id: segmentId,
                sessionId: currentThoughtSegments[index].sessionId,
                startOffset: currentThoughtSegments[index].startOffset,
                endOffset: newEndOffset,
                rawTranscript: newRaw,
                polishedTranscript: currentThoughtSegments[index].polishedTranscript,
                isPolished: currentThoughtSegments[index].isPolished,
                position: currentThoughtSegments[index].position,
                createdAt: currentThoughtSegments[index].createdAt,
                polishedAt: currentThoughtSegments[index].polishedAt
            )
        }

        print("[LongRecordingStore] Appended to thought segment \(segmentId)")
    }

    /// 获取下一个思维段的位置
    func getNextThoughtSegmentPosition(for sessionId: Int64) -> Int {
        let selectSQL = "SELECT COALESCE(MAX(position), -1) FROM thought_segments WHERE session_id = ?"
        var statement: OpaquePointer?
        var maxPosition = -1

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            if sqlite3_step(statement) == SQLITE_ROW {
                maxPosition = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)

        return maxPosition + 1
    }

    /// 加载会话的所有思维段
    func loadThoughtSegments(for sessionId: Int64) {
        var segments: [ThoughtSegment] = []

        let selectSQL = """
            SELECT id, session_id, start_offset, end_offset, raw_transcript, polished_transcript,
                   is_polished, position, created_at, polished_at
            FROM thought_segments
            WHERE session_id = ?
            ORDER BY start_offset ASC
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let sessionId = sqlite3_column_int64(statement, 1)
                let startOffset = sqlite3_column_double(statement, 2)
                let endOffset = sqlite3_column_double(statement, 3)
                let rawTranscript = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let polishedTranscript = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let isPolished = sqlite3_column_int(statement, 6) == 1
                let position = Int(sqlite3_column_int(statement, 7))
                let createdAtString = String(cString: sqlite3_column_text(statement, 8))
                let polishedAtString = sqlite3_column_text(statement, 9).map { String(cString: $0) }

                let segment = ThoughtSegment(
                    id: id,
                    sessionId: sessionId,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    rawTranscript: rawTranscript,
                    polishedTranscript: polishedTranscript,
                    isPolished: isPolished,
                    position: position,
                    createdAt: parseDate(createdAtString) ?? Date(),
                    polishedAt: polishedAtString.flatMap { parseDate($0) }
                )

                segments.append(segment)
            }
        }

        sqlite3_finalize(statement)
        currentThoughtSegments = segments
        print("[LongRecordingStore] Loaded \(segments.count) thought segments for session \(sessionId)")
    }

    /// 获取会话的所有思维段（不修改 currentThoughtSegments）
    func getThoughtSegments(for sessionId: Int64) -> [ThoughtSegment] {
        var segments: [ThoughtSegment] = []

        let selectSQL = """
            SELECT id, session_id, start_offset, end_offset, raw_transcript, polished_transcript,
                   is_polished, position, created_at, polished_at
            FROM thought_segments
            WHERE session_id = ?
            ORDER BY start_offset ASC
            """

        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let sessionId = sqlite3_column_int64(statement, 1)
                let startOffset = sqlite3_column_double(statement, 2)
                let endOffset = sqlite3_column_double(statement, 3)
                let rawTranscript = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let polishedTranscript = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let isPolished = sqlite3_column_int(statement, 6) == 1
                let position = Int(sqlite3_column_int(statement, 7))
                let createdAtString = String(cString: sqlite3_column_text(statement, 8))
                let polishedAtString = sqlite3_column_text(statement, 9).map { String(cString: $0) }

                let segment = ThoughtSegment(
                    id: id,
                    sessionId: sessionId,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    rawTranscript: rawTranscript,
                    polishedTranscript: polishedTranscript,
                    isPolished: isPolished,
                    position: position,
                    createdAt: parseDate(createdAtString) ?? Date(),
                    polishedAt: polishedAtString.flatMap { parseDate($0) }
                )

                segments.append(segment)
            }
        }

        sqlite3_finalize(statement)
        return segments
    }

    /// 获取会话的思维段数量
    func getThoughtSegmentCount(for sessionId: Int64) -> Int {
        let selectSQL = "SELECT COUNT(*) FROM thought_segments WHERE session_id = ?"
        var statement: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, sessionId)
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }

        sqlite3_finalize(statement)
        return count
    }
}
