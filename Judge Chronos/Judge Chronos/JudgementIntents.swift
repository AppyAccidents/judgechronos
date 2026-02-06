import AppIntents
import SwiftUI

// 1. Define the Intent
struct StartFocusSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus Session"
    static var description = IntentDescription("Starts a focus session in Judge Chronos.")
    static var openAppWhenRun: Bool = false // Can run in background!

    @Parameter(title: "Duration (Minutes)")
    var duration: Int
    
    // We can't easily pass complex Category objects without an EntityQuery,
    // so for MVP we'll stick to a default or last used category, or "Deep Work".
    // Or we can perform a simple match by name string if we wanted.
    
    init() {
        self.duration = 25
    }
    
    init(duration: Int) {
        self.duration = duration
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = LocalDataStore.shared
        
        // Find a "Deep Work" category or fallback to first available
        guard let category = store.categories.first(where: { $0.name.localizedCaseInsensitiveContains("Deep") }) 
              ?? store.categories.first else {
            return .result(value: "No categories found.")
        }
        
        store.startFocusSession(durationMinutes: duration, categoryId: category.id)
        
        return .result(value: "Started \(duration)m focus session for \(category.name).")
    }
}

// 2. Define the Provider (Exposes to Shortcuts app)
// 2. Define the Daily Summary Intent
struct GetDailySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Daily Summary"
    static var description = IntentDescription("Returns a summary of today's activity from Judge Chronos.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let store = LocalDataStore.shared
        // We need to fetch today's events.
        // Since `store` holds raw events, we might need to query or filter them.
        // For efficiency, let's reuse the logic if possible, or simple filter.
        
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        let events = store.rawEvents // Note: Logic gap. Store has `rawEvents`. We need `ActivityEvents` (processed).
        // Since we don't have the ViewModel here, we must rely on what's in Store.
        // Store.sessions? Store.rawEvents?
        // Let's assume Store.sessions is the source of truth for "Activity".
        // But `ActivityEvent` is a ViewModel struct.
        // REFACTOR: We need a shared `ActivityService` that logic resides in, NOT ViewModel.
        // For now, let's look at `store.sessions` and convert to a basic summary.
        
        // MVP: Filter contextEvents or sessions.
        // Wait, `ActivityEvent` comes from `RawEvent` mostly.
        let relevant = store.rawEvents.filter {
            $0.startTime >= today && $0.startTime < tomorrow
        }
        
        // This is "Raw". It lacks "Smart Grouping" or "Rules".
        // BUT `store.assignments` exists.
        // Replicating `ActivityViewModel` logic here is risky (Code Duplication).
        // Ideally, `ActivityViewModel` logic should be in `LocalDataStore` or a `ReportService`.
        
        // Let's use `SummaryService` but we need `ActivityEvent`s.
        // Let's create a helper in Store or Service to Map Raw -> Activity.
        
        // QUICK FIX: Just sum up raw apps.
        let duration = relevant.reduce(0) { $0 + ($1.endTime.timeIntervalSince($1.startTime)) }
        let count = relevant.count
        
        return .result(value: "You have recorded \(Formatting.formatDuration(duration)) across \(count) activities today.")
    }
}

// 3. Define the Provider
struct JudgeChronosShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusSessionIntent(),
            phrases: [
                "Start focus in \(.applicationName)",
                "Focus with \(.applicationName)"
            ],
            shortTitle: "Start Focus Session",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: GetDailySummaryIntent(),
            phrases: [
                "Daily Summary in \(.applicationName)",
                "Check Judge Chronos"
            ],
            shortTitle: "Get Daily Summary",
            systemImageName: "doc.text"
        )
    }
}
