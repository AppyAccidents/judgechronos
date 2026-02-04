import Foundation

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
    @Published var aiAvailability: AIAvailability = .unavailable("Checking Apple Intelligence status...")
    @Published var suggestions: [String: AISuggestion] = [:]
    @Published var suggestionErrors: [String: String] = [:]
    @Published var isSuggestingEvents: Set<String> = []
    @Published var categorySuggestions: [String] = []
    @Published var isSuggestingCategories: Bool = false

    private let database: ActivityDatabase
    private let dataStore: LocalDataStore
    private let aiService: AICategoryServiceType

    init(
        database: ActivityDatabase = ActivityDatabase(),
        dataStore: LocalDataStore,
        aiService: AICategoryServiceType = AICategoryService()
    ) {
        self.database = database
        self.dataStore = dataStore
        self.aiService = aiService
        aiAvailability = aiService.availability
    }

    func refresh() {
        Task {
            await loadEvents()
        }
    }

    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rawEvents: [ActivityEvent]
            if rangeEnabled {
                let normalized = normalizedRange()
                rawEvents = try database.fetchEvents(from: normalized.start, to: normalized.end)
            } else {
                rawEvents = try database.fetchEvents(for: selectedDate)
            }
            errorMessage = nil
            showingOnboarding = false
            let withIdle = insertIdleEvents(into: rawEvents)
            events = dataStore.applyCategories(to: withIdle)
            pruneSuggestions()
            lastRefresh = Date()
        } catch ActivityDatabaseError.openFailed {
            showingOnboarding = true
            errorMessage = "Full Disk Access is required to read activity data."
            events = []
        } catch ActivityDatabaseError.queryFailed(let error) {
            showingOnboarding = false
            errorMessage = "Failed to load events: \(error.localizedDescription)"
            events = []
        } catch {
            showingOnboarding = false
            errorMessage = "Failed to load events."
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
        dataStore.assignCategory(eventKey: event.eventKey, categoryId: categoryId)
        events = dataStore.applyCategories(to: events)
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
                    isIdle: true
                )
                output.append(idleEvent)
            }
        }
        return output
    }

    func suggestCategory(for event: ActivityEvent) {
        guard !event.isIdle else { return }
        guard case .available = aiAvailability else {
            suggestionErrors[event.eventKey] = "Apple Intelligence is unavailable."
            return
        }
        guard !isSuggestingEvents.contains(event.eventKey) else { return }
        isSuggestingEvents.insert(event.eventKey)
        suggestionErrors[event.eventKey] = nil
        Task {
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
        let id = dataStore.addCategoryIfNeeded(name: trimmed, color: .blue)
        updateCategory(for: event, categoryId: id)
        suggestions.removeValue(forKey: event.eventKey)
    }

    func dismissSuggestion(for event: ActivityEvent) {
        suggestions.removeValue(forKey: event.eventKey)
    }

    func suggestCategoriesFromRecent() {
        guard case .available = aiAvailability else { return }
        guard !isSuggestingCategories else { return }
        let recentEvents = events.filter { !$0.isIdle }
        guard !recentEvents.isEmpty else { return }
        isSuggestingCategories = true
        Task {
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
        _ = dataStore.addCategoryIfNeeded(name: name, color: .blue)
        categorySuggestions.removeAll { $0 == name }
    }

    func refreshAIAvailability() {
        aiAvailability = aiService.availability
    }

    private func pruneSuggestions() {
        let keys = Set(events.map { $0.eventKey })
        suggestions = suggestions.filter { keys.contains($0.key) }
        suggestionErrors = suggestionErrors.filter { keys.contains($0.key) }
        isSuggestingEvents = Set(isSuggestingEvents.filter { keys.contains($0) })
    }
}
