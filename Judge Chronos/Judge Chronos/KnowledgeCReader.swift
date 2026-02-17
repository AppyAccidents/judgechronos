import Foundation
import SQLite3

enum KnowledgeCReaderError: Error {
    case databaseNotFound(searchedPaths: [String])
    case permissionDenied(path: String?)
    case databaseUnreadable(path: String, underlying: Error)
    case queryFailed(Error)
}

final class KnowledgeCReader {
    static let shared = KnowledgeCReader()
    
    // CoreBiome uses a different reference date (Jan 1 2001)
    static let macAbsoluteTimeIntervalSince1970: TimeInterval = 978307200
    
    private let locator = KnowledgeCDatabaseLocator()

    private static func isPermissionDenied(_ error: Error) -> Bool {
        let lowercased = error.localizedDescription.lowercased()
        return lowercased.contains("authorization")
            || lowercased.contains("permission")
            || lowercased.contains("not authorized")
            || lowercased.contains("operation not permitted")
    }
    
    func fetchEvents(since lastImport: Date?) throws -> [RawEvent] {
        let resolved = locator.resolve()
        let databasePath = resolved.path
        
        do {
            var db: OpaquePointer?
            guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
                let errorText = String(cString: sqlite3_errmsg(db))
                if errorText.localizedCaseInsensitiveContains("no such file") {
                    throw KnowledgeCReaderError.databaseNotFound(searchedPaths: resolved.searchedPaths)
                }
                if errorText.localizedCaseInsensitiveContains("not authorized")
                    || errorText.localizedCaseInsensitiveContains("authorization denied")
                    || errorText.localizedCaseInsensitiveContains("operation not permitted")
                    || errorText.localizedCaseInsensitiveContains("permission denied") {
                    throw KnowledgeCReaderError.permissionDenied(path: databasePath)
                }
                throw KnowledgeCReaderError.databaseUnreadable(
                    path: databasePath,
                    underlying: NSError(domain: "KnowledgeCReader", code: Int(sqlite3_errcode(db)), userInfo: [
                        NSLocalizedDescriptionKey: errorText
                    ])
                )
            }
            defer { sqlite3_close(db) }
            
            // CoreBiome/KnowledgeC query
            // ZOBJECT: Main table
            // ZSTREAMNAME: '/app/usage'
            // ZSTARTDATE: timestamp
            
            var query = """
            SELECT CAST(ZVALUESTRING AS TEXT), CAST(ZSTARTDATE AS REAL), CAST(ZENDDATE AS REAL)
            FROM ZOBJECT
            WHERE ZSTREAMNAME = '/app/usage'
            """

            if lastImport != nil {
                query += " AND ZSTARTDATE > ?"
            }
            query += " ORDER BY ZSTARTDATE ASC"

            var events: [RawEvent] = []
            var scannedRows = 0
            let importedAt = Date()
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw NSError(domain: "KnowledgeCReader", code: Int(sqlite3_errcode(db)), userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ])
            }
            defer { sqlite3_finalize(statement) }

            if let lastImport {
                let macTime = lastImport.timeIntervalSince1970 - Self.macAbsoluteTimeIntervalSince1970
                sqlite3_bind_double(statement, 1, macTime)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                scannedRows += 1
                guard let appNamePtr = sqlite3_column_text(statement, 0) else { continue }
                let appName = String(cString: appNamePtr)
                guard !appName.isEmpty else { continue }

                let startVal = sqlite3_column_double(statement, 1)
                let endVal = sqlite3_column_double(statement, 2)
                if scannedRows <= 3 {
                    print("KnowledgeCReader sample row \(scannedRows): app=\(appName), start=\(startVal), end=\(endVal)")
                }
                let duration = max(0, endVal - startVal)
                guard duration > 0 else { continue }

                let start = Self.macAbsoluteToDate(startVal)
                let end = Self.macAbsoluteToDate(endVal)
                let metadata = "\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))|\(appName)"
                let hash = String(metadata.hashValue)

                events.append(
                    RawEvent(
                        id: UUID(),
                        timestamp: start,
                        duration: duration,
                        bundleId: nil,
                        appName: appName,
                        windowTitle: nil,
                        source: .appUsage,
                        metadataHash: hash,
                        importedAt: importedAt
                    )
                )
            }

            if sqlite3_errcode(db) != SQLITE_OK && sqlite3_errcode(db) != SQLITE_DONE {
                throw NSError(domain: "KnowledgeCReader", code: Int(sqlite3_errcode(db)), userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))
                ])
            }

            if scannedRows > 0, events.isEmpty {
                print("KnowledgeCReader: scanned \(scannedRows) rows but produced 0 events. Check timestamp decoding/schema types.")
            }
            
            return events
            
        } catch {
            if let known = error as? KnowledgeCReaderError {
                throw known
            }
            print("KnowledgeCReader error: \(error)")
            if Self.isPermissionDenied(error) {
                throw KnowledgeCReaderError.permissionDenied(path: databasePath)
            }
            if error.localizedDescription.localizedCaseInsensitiveContains("unable to open database file")
                || error.localizedDescription.localizedCaseInsensitiveContains("open(") {
                throw KnowledgeCReaderError.databaseUnreadable(path: databasePath, underlying: error)
            }
            throw KnowledgeCReaderError.queryFailed(error)
        }
    }
    
    static func macAbsoluteToDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value + macAbsoluteTimeIntervalSince1970)
    }

    static func toTimeInterval(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let numeric = value as? Double { return numeric }
        if let numeric = value as? Int64 { return Double(numeric) }
        if let numeric = value as? Int { return Double(numeric) }
        if let numeric = value as? NSNumber { return numeric.doubleValue }
        return nil
    }
}

private struct KnowledgeCDatabaseLocator {
    private let relativePath = "Library/Application Support/Knowledge/knowledgeC.db"

    func resolve() -> (path: String, searchedPaths: [String]) {
        let fileManager = FileManager.default
        let homeDirectoryPath = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            URL(fileURLWithPath: homeDirectoryPath).appendingPathComponent(relativePath).path,
            NSHomeDirectory() + "/\(relativePath)"
        ]
        var searchedPaths: [String] = []
        for path in candidates {
            if searchedPaths.contains(path) {
                continue
            }
            searchedPaths.append(path)
        }
        return (searchedPaths.first ?? URL(fileURLWithPath: homeDirectoryPath).appendingPathComponent(relativePath).path, searchedPaths)
    }
}
