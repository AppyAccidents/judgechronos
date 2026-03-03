import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum ActivitySQLiteStoreError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

struct ActivitySQLiteState {
    var rawEvents: [RawEvent]
    var sessions: [Session]
    var ruleMatches: [RuleMatch]
    var contextEvents: [ContextEvent]
}

final class ActivitySQLiteStore {
    private let dbPath: String

    init(baseDirectory: URL) {
        self.dbPath = baseDirectory.appendingPathComponent("activity_store.sqlite").path
    }

    func loadState() throws -> ActivitySQLiteState {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try createTablesIfNeeded(db: db)
        return ActivitySQLiteState(
            rawEvents: try loadObjects(db: db, table: "raw_events", orderBy: "timestamp ASC"),
            sessions: try loadObjects(db: db, table: "sessions", orderBy: "start_time ASC"),
            ruleMatches: try loadObjects(db: db, table: "rule_matches", orderBy: "timestamp ASC"),
            contextEvents: try loadObjects(db: db, table: "context_events", orderBy: "timestamp ASC")
        )
    }

    func replaceState(rawEvents: [RawEvent], sessions: [Session], ruleMatches: [RuleMatch], contextEvents: [ContextEvent]) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try createTablesIfNeeded(db: db)
        try execute(db: db, sql: "BEGIN TRANSACTION")
        do {
            try replaceRawEvents(db: db, rawEvents)
            try replaceSessions(db: db, sessions)
            try replaceRuleMatches(db: db, ruleMatches)
            try replaceContextEvents(db: db, contextEvents)
            try execute(db: db, sql: "COMMIT")
        } catch {
            _ = try? execute(db: db, sql: "ROLLBACK")
            throw error
        }
    }

    func fetchSessions(from startDate: Date, to endDate: Date) throws -> [Session] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try createTablesIfNeeded(db: db)

        let sql = """
        SELECT payload
        FROM sessions
        WHERE start_time < ? AND end_time > ?
        ORDER BY start_time ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ActivitySQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, endDate.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, startDate.timeIntervalSince1970)

        var items: [Session] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let length = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: length)
            if let decoded = try? JSONDecoder().decode(Session.self, from: data) {
                items.append(decoded)
            }
        }
        return items
    }

    private func openDatabase() throws -> OpaquePointer {
        let folder = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            throw ActivitySQLiteStoreError.openFailed("Unable to open sqlite store at \(dbPath)")
        }
        return db
    }

    private func createTablesIfNeeded(db: OpaquePointer) throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS raw_events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                metadata_hash TEXT NOT NULL UNIQUE,
                payload BLOB NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_raw_events_timestamp ON raw_events(timestamp)",
            "CREATE INDEX IF NOT EXISTS idx_raw_events_hash ON raw_events(metadata_hash)",
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                payload BLOB NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_sessions_time ON sessions(start_time, end_time)",
            """
            CREATE TABLE IF NOT EXISTS rule_matches (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                payload BLOB NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_rule_matches_session ON rule_matches(session_id)",
            """
            CREATE TABLE IF NOT EXISTS context_events (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                payload BLOB NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_context_events_timestamp ON context_events(timestamp)"
        ]
        for sql in statements {
            try execute(db: db, sql: sql)
        }
    }

    private func replaceRawEvents(db: OpaquePointer, _ rawEvents: [RawEvent]) throws {
        try execute(db: db, sql: "DELETE FROM raw_events")
        let sql = "INSERT INTO raw_events (id, timestamp, metadata_hash, payload) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ActivitySQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let encoder = JSONEncoder()
        for event in rawEvents {
            let payload = try encoder.encode(event)
            sqlite3_bind_text(statement, 1, event.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, event.metadataHash, -1, SQLITE_TRANSIENT)
            payload.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(payload.count), SQLITE_TRANSIENT)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActivitySQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private func replaceSessions(db: OpaquePointer, _ sessions: [Session]) throws {
        try execute(db: db, sql: "DELETE FROM sessions")
        let sql = "INSERT INTO sessions (id, start_time, end_time, payload) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ActivitySQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let encoder = JSONEncoder()
        for session in sessions {
            let payload = try encoder.encode(session)
            sqlite3_bind_text(statement, 1, session.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, session.startTime.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, session.endTime.timeIntervalSince1970)
            payload.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(payload.count), SQLITE_TRANSIENT)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActivitySQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private func replaceRuleMatches(db: OpaquePointer, _ matches: [RuleMatch]) throws {
        try execute(db: db, sql: "DELETE FROM rule_matches")
        let sql = "INSERT INTO rule_matches (id, session_id, timestamp, payload) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ActivitySQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let encoder = JSONEncoder()
        for match in matches {
            let payload = try encoder.encode(match)
            sqlite3_bind_text(statement, 1, match.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, match.sessionId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, match.timestamp.timeIntervalSince1970)
            payload.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(payload.count), SQLITE_TRANSIENT)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActivitySQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private func replaceContextEvents(db: OpaquePointer, _ events: [ContextEvent]) throws {
        try execute(db: db, sql: "DELETE FROM context_events")
        let sql = "INSERT INTO context_events (id, timestamp, payload) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ActivitySQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let encoder = JSONEncoder()
        for event in events {
            let payload = try encoder.encode(event)
            sqlite3_bind_text(statement, 1, event.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, event.timestamp.timeIntervalSince1970)
            payload.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(payload.count), SQLITE_TRANSIENT)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActivitySQLiteStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    private func loadObjects<T: Decodable>(db: OpaquePointer, table: String, orderBy: String) throws -> [T] {
        let sql = "SELECT payload FROM \(table) ORDER BY \(orderBy)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ActivitySQLiteStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let decoder = JSONDecoder()
        var items: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let length = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: length)
            if let decoded = try? decoder.decode(T.self, from: data) {
                items.append(decoded)
            }
        }
        return items
    }

    @discardableResult
    private func execute(db: OpaquePointer, sql: String) throws -> Int32 {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown sqlite error"
            sqlite3_free(errorMessage)
            throw ActivitySQLiteStoreError.stepFailed(message)
        }
        return result
    }
}
