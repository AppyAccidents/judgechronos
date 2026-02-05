import Foundation
import class SQLite.Connection

enum ActivityDatabaseError: Error {
    case openFailed
    case queryFailed(Error)
}

final class ActivityDatabase {
    static let macAbsoluteTimeIntervalSince1970: TimeInterval = 978307200

    private var databasePath: String {
        let home = NSHomeDirectory()
        return home + "/Library/Application Support/Knowledge/knowledgeC.db"
    }

    func openConnection() throws -> Connection {
        do {
            return try Connection(databasePath, readonly: true)
        } catch {
            throw ActivityDatabaseError.openFailed
        }
    }

    func fetchEvents(for date: Date) throws -> [ActivityEvent] {
        return try fetchEvents(from: date, to: date)
    }

    func fetchEvents(from startDate: Date, to endDate: Date) throws -> [ActivityEvent] {
        let db = try openConnection()
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.startOfDay(for: endDate)
        guard let endInclusive = Calendar.current.date(byAdding: .day, value: 1, to: endOfDay) else {
            return []
        }
        let dayStartMacAbsolute = startOfDay.timeIntervalSince1970 - Self.macAbsoluteTimeIntervalSince1970
        let dayEndMacAbsolute = endInclusive.timeIntervalSince1970 - Self.macAbsoluteTimeIntervalSince1970
        let sql = """
        SELECT ZVALUESTRING, ZSTARTDATE, ZENDDATE
        FROM ZOBJECT
        WHERE ZSTREAMNAME = '/app/usage'
          AND ZSTARTDATE >= ?
          AND ZSTARTDATE < ?
        ORDER BY ZSTARTDATE ASC
        """
        do {
            var events: [ActivityEvent] = []
            for row in try db.prepare(sql, dayStartMacAbsolute, dayEndMacAbsolute) {
                guard let appName = row[0] as? String,
                      let start = row[1] as? Double,
                      let end = row[2] as? Double else { continue }
                let startDate = Self.macAbsoluteToDate(start)
                let endDate = Self.macAbsoluteToDate(end)
                let duration = max(0, end - start)
                events.append(ActivityEvent(
                    id: UUID(),
                    eventKey: ActivityEventKey.make(appName: appName, startTime: startDate, endTime: endDate),
                    appName: appName,
                    startTime: startDate,
                    endTime: endDate,
                    duration: duration,
                    categoryId: nil,
                    isIdle: false,
                    source: .appUsage
                ))
            }
            return events
        } catch {
            throw ActivityDatabaseError.queryFailed(error)
        }
    }

    static func macAbsoluteToDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value + macAbsoluteTimeIntervalSince1970)
    }
}
