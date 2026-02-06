import Foundation

struct GroupSuggestion: Identifiable {
    let id = UUID()
    let events: [ActivityEvent]
    let suggestedCategoryId: UUID?
    let title: String
    
    var startTime: Date { events.first?.startTime ?? Date() }
    var endTime: Date { events.last?.endTime ?? Date() }
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
}

class SmartGrouper {
    static let shared = SmartGrouper()
    
    // Config: If events are within X seconds, they might belong together
    private let groupThreshold: TimeInterval = 300 // 5 minutes gaps allowed
    
    func suggestGroups(events: [ActivityEvent], categories: [Category]) -> [GroupSuggestion] {
        // 1. Filter only uncategorized, non-idle events
        let candidates = events.filter { $0.categoryId == nil && !$0.isIdle }.sorted { $0.startTime < $1.startTime }
        
        var suggestions: [GroupSuggestion] = []
        var currentCluster: [ActivityEvent] = []
        
        for event in candidates {
            if let last = currentCluster.last {
                if event.startTime.timeIntervalSince(last.endTime) <= groupThreshold {
                    currentCluster.append(event)
                } else {
                    // Commit current cluster
                    if let group = analyzeCluster(currentCluster, categories: categories) {
                        suggestions.append(group)
                    }
                    currentCluster = [event]
                }
            } else {
                currentCluster = [event]
            }
        }
        
        // Final cluster
        if let group = analyzeCluster(currentCluster, categories: categories) {
            suggestions.append(group)
        }
        
        return suggestions
    }
    
    private func analyzeCluster(_ events: [ActivityEvent], categories: [Category]) -> GroupSuggestion? {
        guard events.count > 1 else { return nil } // Single events aren't "groups" usually
        
        // Duration check: Groups usually represent significant work, say > 15 mins
        let start = events.first!.startTime
        let end = events.last!.endTime
        if end.timeIntervalSince(start) < 900 { return nil } // Min 15 mins
        
        // Heuristic: Most frequent app
        let appCounts = Dictionary(grouping: events, by: { $0.appName })
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        
        guard let primaryApp = appCounts.max(by: { $0.value < $1.value })?.key else { return nil }
        
        // Suggest Category? 
        // For MVP: We don't magically know the category unless we have historical data or heuristics.
        // But we can group them and ask the user to assign ONE category for the whole block.
        
        return GroupSuggestion(
            events: events,
            suggestedCategoryId: nil, // User must decide
            title: "Focus: \(primaryApp) + \(events.count - 1) others"
        )
    }
}
