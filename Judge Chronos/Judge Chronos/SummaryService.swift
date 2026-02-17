import Foundation

@MainActor
class SummaryService {
    static let shared = SummaryService()
    
    func generateDailyRecap(events: [ActivityEvent], dataStore: LocalDataStore) -> String {
        guard !events.isEmpty else { return "No activity recorded today." }
        
        // 1. Total Duration
        let totalDuration = events.reduce(0) { $0 + $1.duration }
        
        // 2. Breakdown by Category
        let byCategory = Dictionary(grouping: events) { $0.categoryId }
        let categoryDurations = byCategory.map { (key, value) -> (String, TimeInterval) in
            let name = dataStore.categoryName(for: key)
            let total = value.reduce(0) { $0 + $1.duration }
            return (name, total)
        }.sorted { $0.1 > $1.1 }
        
        // 3. Top Apps
        let byApp = Dictionary(grouping: events) { $0.appName }
        let topApps = byApp.map { (key, value) -> (String, TimeInterval) in
            (key, value.reduce(0) { $0 + $1.duration })
        }.sorted { $0.1 > $1.1 }.prefix(3)
        
        // 4. Construct Summary
        var lines: [String] = []
        
        lines.append("Daily Recap")
        lines.append("----------")
        lines.append("Total Time: \(Formatting.formatDuration(totalDuration))")
        
        if let topCategory = categoryDurations.first {
            lines.append("Main Focus: \(topCategory.0) (\(Formatting.formatDuration(topCategory.1)))")
        }
        
        lines.append("\nTop Apps:")
        for (app, duration) in topApps {
            lines.append("• \(app): \(Formatting.formatDuration(duration))")
        }
        
        // Idle Analysis
        let idleEvents = events.filter { $0.isIdle }
        let totalIdle = idleEvents.reduce(0) { $0 + $1.duration }
        if totalIdle > 0 {
            lines.append("\nAway Time: \(Formatting.formatDuration(totalIdle))")
            lines.append("(\(idleEvents.count) breaks taken)")
        }
        
        return lines.joined(separator: "\n")
    }
}
