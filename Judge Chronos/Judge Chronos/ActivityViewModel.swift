import Foundation
import SwiftUI

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published private(set) var events: [ActivityEvent] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showingOnboarding: Bool = false
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var rangeEnabled: Bool = false
    @Published var rangeStartDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var rangeEndDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var lastRefresh: Date? = nil
    @Published var aiAvailability: AIAvailability = .unavailable("Not checked yet. Use AI Suggest or Refresh AI Status.")
    @Published var suggestions: [String: AISuggestion] = [:]
    @Published var suggestionErrors: [String: String] = [:]
    @Published var isSuggestingEvents: Set<String> = []
    @Published var categorySuggestions: [String] = []
    @Published var isSuggestingCategories: Bool = false
    @Published var weeklyRecap: WeeklyRecap? = nil

    private let database: ActivityDatabase
    private let dataStore: LocalDataStore
    private let aiService: AICategoryServiceType
    private let calendarService: CalendarService
    private var hasCheckedAIAvailability = false

    init(
        database: ActivityDatabase = ActivityDatabase(),
        dataStore: LocalDataStore,
        aiService: AICategoryServiceType = AICategoryService(),
        calendarService: CalendarService = .shared
    ) {
        self.database = database
        self.dataStore = dataStore
        self.aiService = aiService
        self.calendarService = calendarService
    }

    func refresh() {
        Task {
            await loadEvents()
        }
    }

    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }
        if dataStore.preferences.privateModeEnabled {
            await MainActor.run {
                events = []
                errorMessage = "Private mode is enabled. Activity tracking is paused."
                showingOnboarding = false
                lastRefresh = Date()
            }
            return
        }
        do {
            // Trigger incremental import first
            try await dataStore.performIncrementalImport()

            var rawEvents: [ActivityEvent]
            if rangeEnabled {
                let normalized = normalizedRange()
                rawEvents = dataStore.events(from: normalized.start, to: normalized.end)
            } else {
                let startOfDay = Calendar.current.startOfDay(for: selectedDate)
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86400)
                rawEvents = dataStore.events(from: startOfDay, to: endOfDay)
            }
            if dataStore.preferences.calendarIntegrationEnabled {
                let calendarEvents = try calendarActivityEvents(
                    from: rangeEnabled ? normalizedRange().start : selectedDate,
                    to: rangeEnabled ? normalizedRange().end : selectedDate
                )
                rawEvents.append(contentsOf: calendarEvents)
            }
            if rawEvents.isEmpty, dataStore.rawEvents.isEmpty, dataStore.sessions.isEmpty {
                errorMessage = "No sessions imported yet. Press Refresh after granting Full Disk Access."
            } else {
                errorMessage = nil
            }
            showingOnboarding = false
            let filtered = rawEvents.filter { !dataStore.isExcluded(appName: $0.appName) }
            let withIdle = insertIdleEvents(into: filtered)
            events = dataStore.applyCategories(to: withIdle)
            pruneSuggestions()
            lastRefresh = Date()
        } catch KnowledgeCReaderError.databaseNotFound(let searchedPaths) {
            _ = searchedPaths
            showingOnboarding = true
            errorMessage = "Activity database not found yet. Grant Full Disk Access, relaunch Judge Chronos, then press Refresh."
            events = []
        } catch KnowledgeCReaderError.permissionDenied(let path) {
            _ = path
            showingOnboarding = true
            errorMessage = "Full Disk Access is required for macOS activity data. Open Settings > Privacy & Security > Full Disk Access, enable Judge Chronos, relaunch, then press Refresh."
            events = []
        } catch KnowledgeCReaderError.databaseUnreadable(let path, let error) {
            _ = (path, error)
            showingOnboarding = true
            errorMessage = "Could not open the macOS activity database. Confirm Full Disk Access and relaunch Judge Chronos."
            events = []
        } catch KnowledgeCReaderError.queryFailed(let error) {
            showingOnboarding = false
            errorMessage = "Failed to parse activity data: \(error.localizedDescription)"
            events = []
        } catch {
            showingOnboarding = false
            errorMessage = "Failed to load events: \(error.localizedDescription)"
            events = []
        }
    }

    func updateCategory(for appName: String, categoryId: UUID?) {
        dataStore.assignCategory(appName: appName, categoryId: categoryId)
        events = dataStore.applyCategories(to: events)
    }

    func reapplyCategories() {
        events = dataStore.applyCategories(to: events)
    }

    func updateCategory(for event: ActivityEvent, categoryId: UUID?) {
        if dataStore.sessions.contains(where: { $0.id == event.id }) {
            dataStore.updateSessionCategory(sessionId: event.id, categoryId: categoryId)
        } else {
            dataStore.assignCategory(appName: event.appName, categoryId: categoryId)
        }
        events = dataStore.applyCategories(to: events)
    }

    func exportData() throws -> Data {
        return try DataExporter.shared.exportAllData(from: dataStore)
    }

    func normalizedRange() -> (start: Date, end: Date) {
        if rangeStartDate <= rangeEndDate {
            return (rangeStartDate, rangeEndDate)
        }
        return (rangeEndDate, rangeStartDate)
    }

    func insertIdleEvents(into events: [ActivityEvent]) -> [ActivityEvent] {
        let sorted = events.sorted { $0.startTime < $1.startTime }
        guard sorted.count > 1 else { return sorted }
        var output: [ActivityEvent] = []
        let idleThreshold: TimeInterval = 5 * 60
        for index in 0..<sorted.count {
            let current = sorted[index]
            output.append(current)
            guard index + 1 < sorted.count else { continue }
            let next = sorted[index + 1]
            let sameDay = Calendar.current.isDate(current.endTime, inSameDayAs: next.startTime)
            let gap = next.startTime.timeIntervalSince(current.endTime)
            if sameDay, gap >= idleThreshold {
                let idleEvent = ActivityEvent(
                    id: UUID(),
                    eventKey: ActivityEventKey.make(appName: "Idle", startTime: current.endTime, endTime: next.startTime),
                    appName: "Idle",
                    startTime: current.endTime,
                    endTime: next.startTime,
                    duration: gap,
                    categoryId: nil,
                    isIdle: true,
                    source: .idle
                )
                output.append(idleEvent)
            }
        }
        return output
    }

    func suggestCategory(for event: ActivityEvent) {
        guard !event.isIdle else { return }
        guard !isSuggestingEvents.contains(event.eventKey) else { return }
        isSuggestingEvents.insert(event.eventKey)
        suggestionErrors[event.eventKey] = nil
        Task {
            let available = await ensureAIAvailable()
            guard available else {
                await MainActor.run {
                    suggestionErrors[event.eventKey] = "Apple Intelligence is unavailable."
                    isSuggestingEvents.remove(event.eventKey)
                }
                return
            }
            do {
                let suggestion = try await aiService.suggestCategory(for: event)
                await MainActor.run {
                    suggestions[event.eventKey] = suggestion
                    isSuggestingEvents.remove(event.eventKey)
                }
            } catch {
                await MainActor.run {
                    suggestionErrors[event.eventKey] = error.localizedDescription
                    isSuggestingEvents.remove(event.eventKey)
                }
            }
        }
    }

    func applySuggestion(for event: ActivityEvent) {
        guard let suggestion = suggestions[event.eventKey] else { return }
        let trimmed = suggestion.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = dataStore.addCategoryIfNeeded(name: trimmed, color: AppTheme.Colors.primary)
        updateCategory(for: event, categoryId: id)
        suggestions.removeValue(forKey: event.eventKey)
    }

    func dismissSuggestion(for event: ActivityEvent) {
        suggestions.removeValue(forKey: event.eventKey)
    }

    func suggestCategoriesFromRecent() {
        guard !isSuggestingCategories else { return }
        let recentEvents = events.filter { !$0.isIdle }
        guard !recentEvents.isEmpty else { return }
        isSuggestingCategories = true
        Task {
            let available = await ensureAIAvailable()
            guard available else {
                await MainActor.run {
                    categorySuggestions = []
                    isSuggestingCategories = false
                }
                return
            }
            do {
                let result = try await aiService.suggestCategories(from: recentEvents)
                await MainActor.run {
                    categorySuggestions = Array(Set(result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).filter { !$0.isEmpty }.sorted()
                    isSuggestingCategories = false
                }
            } catch {
                await MainActor.run {
                    categorySuggestions = []
                    isSuggestingCategories = false
                }
            }
        }
    }

    func applyCategorySuggestion(_ name: String) {
        _ = dataStore.addCategoryIfNeeded(name: name, color: AppTheme.Colors.primary)
        categorySuggestions.removeAll { $0 == name }
    }

    func refreshAIAvailability() {
        Task {
            let availability = await aiService.refreshAvailability()
            await MainActor.run {
                aiAvailability = availability
                hasCheckedAIAvailability = true
            }
        }
    }

    private func ensureAIAvailable() async -> Bool {
        if !hasCheckedAIAvailability {
            let availability = await aiService.refreshAvailability()
            await MainActor.run {
                aiAvailability = availability
                hasCheckedAIAvailability = true
            }
        }
        if case .available = aiAvailability {
            return true
        }
        return false
    }

    func loadWeeklyRecap(referenceDate: Date = Date()) async {
        do {
            let calendar = Calendar.current
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? calendar.startOfDay(for: referenceDate)
            guard let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) else { return }
            guard let previousStart = calendar.date(byAdding: .day, value: -7, to: startOfWeek),
                  let previousEnd = calendar.date(byAdding: .day, value: -1, to: startOfWeek) else { return }

            var currentRaw = dataStore.events(from: startOfWeek, to: endOfWeek)
            var previousRaw = dataStore.events(from: previousStart, to: previousEnd)
            if dataStore.preferences.calendarIntegrationEnabled {
                currentRaw.append(contentsOf: try calendarActivityEvents(from: startOfWeek, to: endOfWeek))
                previousRaw.append(contentsOf: try calendarActivityEvents(from: previousStart, to: previousEnd))
            }
            let current = dataStore.applyCategories(to: currentRaw.filter { !$0.isIdle && !dataStore.isExcluded(appName: $0.appName) })
            let previous = dataStore.applyCategories(to: previousRaw.filter { !$0.isIdle && !dataStore.isExcluded(appName: $0.appName) })

            let currentTotals = aggregateByCategory(events: current)
            let previousTotals = aggregateByCategory(events: previous)
            let recap = WeeklyRecap(
                startDate: startOfWeek,
                endDate: endOfWeek,
                topCategories: topCategories(from: currentTotals),
                deltaMinutes: currentTotals.totalMinutes - previousTotals.totalMinutes
            )
            await MainActor.run {
                weeklyRecap = recap
            }
        } catch {
            await MainActor.run {
                weeklyRecap = nil
            }
        }
    }

    private func pruneSuggestions() {
        let keys = Set(events.map { $0.eventKey })
        suggestions = suggestions.filter { keys.contains($0.key) }
        suggestionErrors = suggestionErrors.filter { keys.contains($0.key) }
        isSuggestingEvents = Set(isSuggestingEvents.filter { keys.contains($0) })
    }

    private func calendarActivityEvents(from startDate: Date, to endDate: Date) throws -> [ActivityEvent] {
        guard calendarService.hasAccess else { return [] }
        let startOfDay = Calendar.current.startOfDay(for: startDate)
        let endOfDay = Calendar.current.startOfDay(for: endDate)
        guard let endInclusive = Calendar.current.date(byAdding: .day, value: 1, to: endOfDay) else {
            return []
        }
        let meetingsCategoryId = dataStore.addCategoryIfNeeded(name: "Meetings", color: AppTheme.Colors.secondary)
        let events = try calendarService.fetchEvents(from: startOfDay, to: endInclusive)
        return events.map { event in
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = title?.isEmpty == false ? "Meeting — \(title!)" : "Meeting"
            let key = ActivityEventKey.make(appName: name, startTime: event.startDate, endTime: event.endDate)
            return ActivityEvent(
                id: UUID(),
                eventKey: key,
                appName: name,
                startTime: event.startDate,
                endTime: event.endDate,
                duration: event.endDate.timeIntervalSince(event.startDate),
                categoryId: meetingsCategoryId,
                isIdle: false,
                source: .calendar
            )
        }
    }

    private func aggregateByCategory(events: [ActivityEvent]) -> CategoryTotals {
        var totals: [UUID?: TimeInterval] = [:]
        for event in events {
            totals[event.categoryId, default: 0] += event.duration
        }
        let totalMinutes = Int(totals.values.reduce(0, +) / 60)
        return CategoryTotals(totals: totals, totalMinutes: totalMinutes)
    }

    private func topCategories(from totals: CategoryTotals, limit: Int = 3) -> [(UUID?, Int)] {
        totals.totals
            .map { ($0.key, Int($0.value / 60)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0 }
    }
}

struct WeeklyRecap {
    let startDate: Date
    let endDate: Date
    let topCategories: [(UUID?, Int)]
    let deltaMinutes: Int
}

private struct CategoryTotals {
    let totals: [UUID?: TimeInterval]
    let totalMinutes: Int
}
