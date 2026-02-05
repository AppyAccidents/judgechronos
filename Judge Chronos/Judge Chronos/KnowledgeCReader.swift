import Foundation
import SQLite

enum KnowledgeCReaderError: Error {
    case databaseNotFound
    case permissionDenied
    case queryFailed(Error)
}

final class KnowledgeCReader {
    static let shared = KnowledgeCReader()
    
    // CoreBiome uses a different reference date (Jan 1 2001)
    static let macAbsoluteTimeIntervalSince1970: TimeInterval = 978307200
    
    private var databasePath: String {
        let home = NSHomeDirectory()
        return home + "/Library/Application Support/Knowledge/knowledgeC.db"
    }
    
    func fetchEvents(since lastImport: Date?) throws -> [RawEvent] {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw KnowledgeCReaderError.databaseNotFound
        }
        
        do {
            let db = try Connection(databasePath, readonly: true)
            
            // CoreBiome/KnowledgeC query
            // ZOBJECT: Main table
            // ZSTREAMNAME: '/app/usage'
            // ZSTARTDATE: timestamp
            
            var query = """
            SELECT ZVALUESTRING, ZSTARTDATE, ZENDDATE
            FROM ZOBJECT
            WHERE ZSTREAMNAME = '/app/usage'
            """
            
            var params: [Binding?] = []
            
            if let lastImport = lastImport {
                query += " AND ZSTARTDATE > ?"
                let macTime = lastImport.timeIntervalSince1970 - Self.macAbsoluteTimeIntervalSince1970
                params.append(macTime)
            }
            
            query += " ORDER BY ZSTARTDATE ASC"
            
            var events: [RawEvent] = []
            let importedAt = Date()
            
            for row in try db.prepare(query, params) {
                guard let appName = row[0] as? String,
                      let startVal = row[1] as? Double,
                      let endVal = row[2] as? Double else { continue }
                
                let start = Self.macAbsoluteToDate(startVal)
                let end = Self.macAbsoluteToDate(endVal)
                let duration = max(0, endVal - startVal)
                
                guard duration > 0 else { continue }
                
                // Deduplication Hash: Start + End + AppName
                let metadata = "\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))|\(appName)"
                let hash = String(metadata.hashValue) // fast simple hash for now
                
                let event = RawEvent(
                    id: UUID(),
                    timestamp: start,
                    duration: duration,
                    bundleId: nil, // Bundle ID is often in ZCREATIONDATE or other joined tables, keeping simple for now
                    appName: appName,
                    windowTitle: nil, // Not available in basic knowledgeC /app/usage
                    source: .appUsage,
                    metadataHash: hash,
                    importedAt: importedAt
                )
                
                events.append(event)
            }
            
            return events
            
        } catch {
            print("KnowledgeCReader error: \(error)")
            // If we can't open permissions, it's likely Full Disk Access
            if error.localizedDescription.contains("authorization") || error.localizedDescription.contains("permission") {
                throw KnowledgeCReaderError.permissionDenied
            }
            throw KnowledgeCReaderError.queryFailed(error)
        }
    }
    
    static func macAbsoluteToDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value + macAbsoluteTimeIntervalSince1970)
    }
}
