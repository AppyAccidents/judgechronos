import Foundation

struct Report: Encodable {
    let interval: DateInterval
    let totalDuration: TimeInterval
    let byProject: [UUID?: TimeInterval]
    let byCategory: [UUID?: TimeInterval]
    let byTag: [UUID: TimeInterval]
    let uncategorizedDuration: TimeInterval
}

struct ComparisonReport: Encodable {
    let current: Report
    let previous: Report
    let deltaDuration: TimeInterval
}

final class ReportingService {
    static let shared = ReportingService()
    
    func generateReport(for interval: DateInterval, sessions: [Session]) -> Report {
        // Filter sessions within interval
        // Note: We might need to handle sessions that partially overlap the interval (clipping),
        // but for MVP, strict inclusion or start-time based is often enough.
        // Let's do partial clipping for accuracy.
        
        var totalDuration: TimeInterval = 0
        var byProject: [UUID?: TimeInterval] = [:]
        var byCategory: [UUID?: TimeInterval] = [:]
        var byTag: [UUID: TimeInterval] = [:]
        var uncategorized: TimeInterval = 0
        
        for session in sessions {
            // Check overlap
            let overlapStart = max(session.startTime, interval.start)
            let overlapEnd = min(session.endTime, interval.end)
            
            if overlapStart < overlapEnd {
                let duration = overlapEnd.timeIntervalSince(overlapStart)
                
                // Skip idle/private sessions if we want "Active Work" report?
                // Roadmap says "Reporting that answers real questions".
                // Usually we exclude Idle from "Total Work", but include it in specific queries.
                // Let's exclude .isIdle from general totals for now.
                if session.isIdle { continue }
                if session.isPrivate { continue }
                
                totalDuration += duration
                
                // Project
                byProject[session.projectId, default: 0] += duration
                
                // Category
                byCategory[session.categoryId, default: 0] += duration
                if session.categoryId == nil {
                    uncategorized += duration
                }
                
                // Tags
                for tagId in session.tagIds {
                    byTag[tagId, default: 0] += duration
                }
            }
        }
        
        return Report(
            interval: interval,
            totalDuration: totalDuration,
            byProject: byProject,
            byCategory: byCategory,
            byTag: byTag,
            uncategorizedDuration: uncategorized
        )
    }
    
    func compare(current: Report, previous: Report) -> ComparisonReport {
        return ComparisonReport(
            current: current,
            previous: previous,
            deltaDuration: current.totalDuration - previous.totalDuration
        )
    }
}
