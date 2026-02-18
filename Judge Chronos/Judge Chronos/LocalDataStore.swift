import Foundation
import SwiftUI

enum SaveUrgency {
    case immediate
    case deferred
}

@MainActor
final class LocalDataStore: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var assignments: [String: UUID] = [:]
    @Published private(set) var exclusions: [ExclusionRule] = []
    @Published private(set) var focusSessions: [FocusSession] = []
    @Published private(set) var goals: [Goal] = []
    
    static let shared = LocalDataStore() // For App Intents access
    
    // Phase 0: New Data Models
    @Published private(set) var rawEvents: [RawEvent] = []
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var ruleMatches: [RuleMatch] = []
    @Published private(set) var contextEvents: [ContextEvent] = []
    
    @Published var preferences: UserPreferences = .default

    private let fileURL: URL
    private let persistQueue = DispatchQueue(label: "JudgeChronos.LocalDataStore.persist", qos: .utility)
    private var deferredPersistWorkItem: DispatchWorkItem?
    private let deferredPersistDelay: TimeInterval = 2.0
    private var isImporting = false
    private var lastImportAttempt: Date?
    private let importThrottleInterval: TimeInterval = 3.0
    private let maxContextEvents = 2_000

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let appURL = baseURL?.appendingPathComponent("JudgeChronos", isDirectory: true)
            self.fileURL = (appURL ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("local_data.json")
        }
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(LocalData.self, from: data)
            categories = decoded.categories
            rules = decoded.rules
            assignments = decoded.assignments
            exclusions = decoded.exclusions
            focusSessions = decoded.focusSessions
            goals = decoded.goals
            rawEvents = decoded.rawEvents
            sessions = decoded.sessions
            projects = decoded.projects
            tags = decoded.tags
            ruleMatches = decoded.ruleMatches
            contextEvents = decoded.contextEvents
            preferences = decoded.preferences
        } catch {
            categories = []
            rules = []
            assignments = [:]
            exclusions = []
            focusSessions = []
            goals = []
            rawEvents = []
            sessions = []
            projects = []
            tags = []
            ruleMatches = []
            contextEvents = []
            preferences = .default
            persist(.immediate)
        }
    }

    func save() {
        persist(.immediate)
    }

    func persist(_ urgency: SaveUrgency) {
        switch urgency {
        case .immediate:
            deferredPersistWorkItem?.cancel()
            deferredPersistWorkItem = nil
            enqueuePersist(snapshot())
        case .deferred:
            deferredPersistWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.enqueuePersist(self.snapshot())
                self.deferredPersistWorkItem = nil
            }
            deferredPersistWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + deferredPersistDelay, execute: workItem)
        }
    }

    private func enqueuePersist(_ payload: LocalData) {
        let destination = fileURL
        persistQueue.async {
            do {
                let containerURL = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
                let data = try JSONEncoder().encode(payload)
                try data.write(to: destination, options: [.atomic])
            } catch {
                // Keep silent to avoid crashing the app. We'll show errors in the UI when needed.
            }
        }
    }

    func addCategory(name: String, color: Color) {
        let newCategory = Category(id: UUID(), name: name, colorHex: color.toHex())
        categories.append(newCategory)
        persist(.immediate)
    }

    func updateCategory(_ category: Category, name: String, color: Color) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index].name = name
        categories[index].colorHex = color.toHex()
        persist(.immediate)
    }

    func deleteCategory(_ category: Category) {
        categories.removeAll { $0.id == category.id }
        rules.removeAll { $0.categoryId == category.id }
        assignments = assignments.filter { $0.value != category.id }
        persist(.immediate)
    }

    func addRule(name: String, appNamePattern: String?, categoryId: UUID?, priority: Int = 10, markAsPrivate: Bool = false) {
        let rule = Rule(
            id: UUID(),
            name: name,
            priority: priority,
            isEnabled: true,
            bundleIdPattern: nil,
            appNamePattern: appNamePattern,
            windowTitlePattern: nil,
            minDuration: nil,
            targetProjectId: nil,
            targetCategoryId: categoryId,
            targetTagIds: [],
            markAsPrivate: markAsPrivate
        )
        rules.append(rule)
        persist(.immediate)
    }

    func deleteRule(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        persist(.immediate)
    }

    func updateRule(_ rule: Rule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persist(.immediate)
    }

    func addExclusion(pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let rule = ExclusionRule(id: UUID(), pattern: trimmed)
        exclusions.append(rule)
        persist(.immediate)
    }

    func deleteExclusion(_ rule: ExclusionRule) {
        exclusions.removeAll { $0.id == rule.id }
        persist(.immediate)
    }
    
    func addContextEvent(_ event: ContextEvent) {
        contextEvents.append(event)
        if contextEvents.count > maxContextEvents {
            contextEvents.removeFirst(contextEvents.count - maxContextEvents)
        }
        persist(.deferred)
    }
    
    func addRawEvent(_ event: RawEvent) {
        rawEvents.append(event)
        // Trigger session derivation for this new event immediately?
        // Phase 2: Yes, we should update sessions.
        let matches = SessionManager.shared.updateSessions(&sessions, with: [event], rules: rules)
        if !matches.isEmpty {
            ruleMatches.append(contentsOf: matches)
        }
        persist(.deferred)
    }

    func isExcluded(appName: String) -> Bool {
        let lowercased = appName.lowercased()
        return exclusions.contains { lowercased.contains($0.pattern.lowercased()) }
    }

    func assignCategory(appName: String, categoryId: UUID?) {
        // Deprecated: legacy per-app assignments. Kept for migration compatibility.
        if let categoryId = categoryId {
            assignments[appName] = categoryId
        } else {
            assignments.removeValue(forKey: appName)
        }
        persist(.immediate)
    }

    func assignCategory(eventKey: String, categoryId: UUID?) {
        if let categoryId = categoryId {
            assignments[eventKey] = categoryId
        } else {
            assignments.removeValue(forKey: eventKey)
        }
        persist(.immediate)
    }

    func categoryForEvent(_ event: ActivityEvent) -> UUID? {
        // Phase 2: Check Session Assignment first
        if let session = sessions.first(where: { $0.id == event.id }), let manual = session.categoryId {
            return manual
        }
        
        if let assignment = assignments[event.eventKey] {
            return assignment
        }
        if let focusCategory = focusCategoryForEvent(event) {
            return focusCategory
        }
        if let legacy = assignments[event.appName] {
            return legacy
        }
        return ruleCategoryForApp(event.appName)
    }
    
    func assignmentForEvent(_ event: ActivityEvent) -> UUID? {
        // Phase 2: Check Session Assignment first
        if let session = sessions.first(where: { $0.id == event.id }) {
            return session.categoryId
        }
        
        if let assignment = assignments[event.eventKey] {
            return assignment
        }
        return assignments[event.appName]
    }

    func ruleCategoryForApp(_ appName: String) -> UUID? {
        let lowercased = appName.lowercased()
        for rule in rules {
            if lowercased.contains(rule.pattern.lowercased()) {
                return rule.categoryId
            }
        }
        return nil
    }

    func categoryId(named name: String) -> UUID? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return categories.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized })?.id
    }

    func addCategoryIfNeeded(name: String, color: Color = AppTheme.Colors.primary) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = categoryId(named: trimmed) {
            return existing
        }
        let newCategory = Category(id: UUID(), name: trimmed, colorHex: color.toHex())
        categories.append(newCategory)
        persist(.immediate)
        return newCategory.id
    }

    func applyCategories(to events: [ActivityEvent]) -> [ActivityEvent] {
        events.map { event in
            var updated = event
            if event.isIdle {
                updated.categoryId = nil
            } else if event.source == .calendar {
                if let assignment = assignments[event.eventKey] {
                    updated.categoryId = assignment
                }
            } else {
                updated.categoryId = categoryForEvent(event)
            }
            return updated
        }
    }

    func addGoal(categoryId: UUID, minutesPerDay: Int) {
        let newGoal = Goal(id: UUID(), categoryId: categoryId, minutesPerDay: minutesPerDay)
        goals.append(newGoal)
        persist(.immediate)
    }

    func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        persist(.immediate)
    }

    func startFocusSession(durationMinutes: Int, categoryId: UUID) {
        let start = Date()
        let end = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: start) ?? start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let session = FocusSession(id: UUID(), startTime: start, endTime: end, categoryId: categoryId)
        focusSessions.append(session)
        persist(.immediate)
    }

    func endActiveFocusSession() {
        guard let index = activeFocusSessionIndex() else { return }
        focusSessions[index].endTime = Date()
        persist(.immediate)
    }

    func activeFocusSession() -> FocusSession? {
        guard let index = activeFocusSessionIndex() else { return nil }
        return focusSessions[index]
    }

    private func activeFocusSessionIndex() -> Int? {
        let now = Date()
        return focusSessions.lastIndex(where: { $0.startTime <= now && $0.endTime >= now })
    }

    func focusCategoryForEvent(_ event: ActivityEvent) -> UUID? {
        for session in focusSessions {
            let overlaps = event.startTime < session.endTime && event.endTime > session.startTime
            if overlaps {
                return session.categoryId
            }
        }
        return nil
    }

    func updatePreferences(_ update: (inout UserPreferences) -> Void) {
        var current = preferences
        update(&current)
        preferences = current
        persist(.immediate)
    }

    func categoryName(for id: UUID?) -> String {
        guard let id = id else { return "Uncategorized" }
        return categories.first(where: { $0.id == id })?.name ?? "Uncategorized"
    }

    func categoryColor(for id: UUID?) -> Color {
        guard let id = id,
              let hex = categories.first(where: { $0.id == id })?.colorHex,
              let color = Color(hex: hex) else {
            return Color.gray
        }
        return color
    }
    
    // MARK: - Phase 1: extraction & Retrieval
    
    func performIncrementalImport() async throws {
        if isImporting {
            return
        }
        let now = Date()
        if let lastImportAttempt, now.timeIntervalSince(lastImportAttempt) < importThrottleInterval {
            return
        }
        isImporting = true
        lastImportAttempt = now
        defer { isImporting = false }

        let lastImport = preferences.lastImportTimestamp
        let newEvents = try KnowledgeCReader.shared.fetchEvents(since: lastImport)
        _ = applyImportedEvents(newEvents)
    }

    @discardableResult
    func applyImportedEvents(_ newEvents: [RawEvent]) -> Int {
        let existingHashes = Set(rawEvents.map { $0.metadataHash })
        var addedEvents: [RawEvent] = []

        for event in newEvents where !existingHashes.contains(event.metadataHash) {
            rawEvents.append(event)
            addedEvents.append(event)
        }

        if !addedEvents.isEmpty {
            rawEvents.sort { $0.timestamp < $1.timestamp }
            let matches = SessionManager.shared.updateSessions(&sessions, with: addedEvents, rules: rules)
            ruleMatches.append(contentsOf: matches)
        }

        // Update watermark even when all rows were duplicates, to avoid rescanning.
        if let latestScanned = newEvents.last?.timestamp {
            preferences.lastImportTimestamp = latestScanned
        }

        if !addedEvents.isEmpty || newEvents.last?.timestamp != nil {
            persist(.deferred)
        }
        return addedEvents.count
    }
    
    func updateSessionCategory(sessionId: UUID, categoryId: UUID?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].categoryId = categoryId
        persist(.immediate)
    }
    
    func events(from startDate: Date, to endDate: Date) -> [ActivityEvent] {
        // Phase 2: Read from Derived Sessions instead of Raw Events!
        let filtered = sessions.filter {
            $0.startTime < endDate && $0.endTime > startDate
        }
        
        return filtered.map { session in
            ActivityEvent(
                id: session.id, // Use Session ID
                eventKey: "session|\(session.id.uuidString)", // Unique key for session
                appName: session.sourceApp,
                startTime: session.startTime,
                endTime: session.endTime,
                duration: session.duration,
                categoryId: session.categoryId, // Use Session's manually assigned category
                isIdle: session.isIdle,
                source: session.isIdle ? .idle : .appUsage
            )
        }
    }

    func snapshot() -> LocalData {
        return LocalData(
            categories: categories,
            rules: rules,
            assignments: assignments,
            exclusions: exclusions,
            focusSessions: focusSessions,
            goals: goals,
            preferences: preferences,
            rawEvents: rawEvents,
            sessions: sessions,
            projects: projects,
            tags: tags,
            ruleMatches: ruleMatches,
            contextEvents: contextEvents
        )
    }
    
}
