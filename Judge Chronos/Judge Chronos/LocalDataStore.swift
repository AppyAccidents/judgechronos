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

    static let shared = LocalDataStore(channel: .current)

    @Published private(set) var rawEvents: [RawEvent] = []
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var ruleMatches: [RuleMatch] = []
    @Published private(set) var contextEvents: [ContextEvent] = []

    @Published var preferences: UserPreferences = .default
    let channel: DistributionChannel

    private let fileURL: URL
    private let sqliteStore: ActivitySQLiteStore
    private let ingestionProvider: ActivityIngestionProvider
    private let persistQueue = DispatchQueue(label: "JudgeChronos.LocalDataStore.persist", qos: .utility)
    private var deferredPersistWorkItem: DispatchWorkItem?
    private let deferredPersistDelay: TimeInterval = 2.0
    private var isImporting = false
    private var lastImportAttempt: Date?
    private let importThrottleInterval: TimeInterval = 3.0
    private let maxContextEvents = 2_000
    private var rawEventHashes: Set<String> = []

    init(
        fileURL: URL? = nil,
        channel: DistributionChannel = .current,
        ingestionProvider: ActivityIngestionProvider? = nil
    ) {
        self.channel = channel
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let appURL = baseURL?.appendingPathComponent("JudgeChronos", isDirectory: true)
            self.fileURL = (appURL ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("local_data.json")
        }
        self.sqliteStore = ActivitySQLiteStore(baseDirectory: self.fileURL.deletingLastPathComponent())
        if let ingestionProvider {
            self.ingestionProvider = ingestionProvider
        } else {
            #if APPSTORE
            self.ingestionProvider = ForegroundContextIngestionProvider()
            #else
            self.ingestionProvider = channel == .macAppStore
                ? ForegroundContextIngestionProvider()
                : KnowledgeCIngestionProvider()
            #endif
        }
        load()
    }

    var activityCapabilities: ActivityCapabilities {
        ingestionProvider.capabilities
    }

    func load() {
        var decoded: LocalData?
        if let data = try? Data(contentsOf: fileURL),
           let parsed = try? JSONDecoder().decode(LocalData.self, from: data) {
            decoded = parsed
        }

        categories = decoded?.categories ?? []
        rules = decoded?.rules ?? []
        assignments = decoded?.assignments ?? [:]
        exclusions = decoded?.exclusions ?? []
        focusSessions = decoded?.focusSessions ?? []
        goals = decoded?.goals ?? []
        projects = decoded?.projects ?? []
        tags = decoded?.tags ?? []
        preferences = decoded?.preferences ?? .default

        if let sqliteState = try? sqliteStore.loadState() {
            rawEvents = sqliteState.rawEvents
            sessions = sqliteState.sessions
            ruleMatches = sqliteState.ruleMatches
            contextEvents = sqliteState.contextEvents
        }

        if rawEvents.isEmpty, let migrated = decoded?.migratedRawEvents, !migrated.isEmpty {
            rawEvents = migrated
        }
        if sessions.isEmpty, let migrated = decoded?.migratedSessions, !migrated.isEmpty {
            sessions = migrated
        }
        if ruleMatches.isEmpty, let migrated = decoded?.migratedRuleMatches, !migrated.isEmpty {
            ruleMatches = migrated
        }
        if contextEvents.isEmpty, let migrated = decoded?.migratedContextEvents, !migrated.isEmpty {
            contextEvents = migrated
        }

        rawEvents.sort { $0.timestamp < $1.timestamp }
        sessions.sort { $0.startTime < $1.startTime }
        contextEvents.sort { $0.timestamp < $1.timestamp }
        ruleMatches.sort { $0.timestamp < $1.timestamp }
        rawEventHashes = Set(rawEvents.map(\.metadataHash))

        if decoded == nil {
            persist(.immediate)
        } else {
            persist(.deferred)
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
            enqueuePersist(configurationSnapshot: configurationSnapshot(), activityState: activityStateSnapshot())
        case .deferred:
            deferredPersistWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.enqueuePersist(configurationSnapshot: self.configurationSnapshot(), activityState: self.activityStateSnapshot())
                self.deferredPersistWorkItem = nil
            }
            deferredPersistWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + deferredPersistDelay, execute: workItem)
        }
    }

    private func enqueuePersist(configurationSnapshot: LocalData, activityState: ActivitySQLiteState) {
        let destination = fileURL
        let sqlite = sqliteStore
        persistQueue.async {
            do {
                let containerURL = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
                let data = try JSONEncoder().encode(configurationSnapshot)
                try data.write(to: destination, options: [.atomic])
                try sqlite.replaceState(
                    rawEvents: activityState.rawEvents,
                    sessions: activityState.sessions,
                    ruleMatches: activityState.ruleMatches,
                    contextEvents: activityState.contextEvents
                )
            } catch {
                // Keep silent to avoid crashing the app.
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
        rules.removeAll { $0.targetCategoryId == category.id }
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
        reevaluateAllSessions()
        persist(.immediate)
    }

    func deleteRule(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        reevaluateAllSessions()
        persist(.immediate)
    }

    func updateRule(_ rule: Rule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        reevaluateAllSessions()
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
        contextEvents.sort { $0.timestamp < $1.timestamp }
        if contextEvents.count > maxContextEvents {
            contextEvents.removeFirst(contextEvents.count - maxContextEvents)
        }
        let affected = sessionIds(overlapping: event.timestamp.addingTimeInterval(-60), and: event.timestamp.addingTimeInterval(60))
        applyContextFusion(to: affected, meetings: [])
        reevaluateSessions(sessionIds: affected)
        persist(.deferred)
    }

    func addRawEvent(_ event: RawEvent) {
        guard !rawEventHashes.contains(event.metadataHash) else { return }
        rawEvents.append(event)
        rawEvents.sort { $0.timestamp < $1.timestamp }
        rawEventHashes.insert(event.metadataHash)
        let changed = SessionManager.shared.updateSessions(&sessions, with: [event])
        sessions.sort { $0.startTime < $1.startTime }
        applyContextFusion(to: changed, meetings: [])
        reevaluateSessions(sessionIds: changed)
        persist(.deferred)
    }

    func isExcluded(appName: String) -> Bool {
        let lowercased = appName.lowercased()
        return exclusions.contains { lowercased.contains($0.pattern.lowercased()) }
    }

    func assignCategory(appName: String, categoryId: UUID?) {
        if let categoryId {
            assignments[appName] = categoryId
        } else {
            assignments.removeValue(forKey: appName)
        }
        persist(.immediate)
    }

    func assignCategory(eventKey: String, categoryId: UUID?) {
        if let categoryId {
            assignments[eventKey] = categoryId
        } else {
            assignments.removeValue(forKey: eventKey)
        }
        persist(.immediate)
    }

    func categoryForEvent(_ event: ActivityEvent) -> UUID? {
        if let session = sessions.first(where: { $0.id == event.id }), let explicit = session.categoryId {
            return explicit
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
        if let session = sessions.first(where: { $0.id == event.id }),
           let rule = RuleMatcher.shared.evaluate(session: session, rules: rules) {
            return rule.rule.targetCategoryId
        }
        return nil
    }

    func assignmentForEvent(_ event: ActivityEvent) -> UUID? {
        if let session = sessions.first(where: { $0.id == event.id }) {
            return session.categoryId
        }
        if let assignment = assignments[event.eventKey] {
            return assignment
        }
        return assignments[event.appName]
    }

    func ruleCategoryForApp(_ appName: String) -> UUID? {
        let synthetic = Session(
            id: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(60),
            sourceApp: appName,
            rawEventIds: [],
            isIdle: false
        )
        return RuleMatcher.shared.evaluate(session: synthetic, rules: rules)?.rule.targetCategoryId
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
        goals.append(Goal(id: UUID(), categoryId: categoryId, minutesPerDay: minutesPerDay))
        persist(.immediate)
    }

    func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        persist(.immediate)
    }

    func startFocusSession(durationMinutes: Int, categoryId: UUID) {
        let start = Date()
        let end = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: start) ?? start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        focusSessions.append(FocusSession(id: UUID(), startTime: start, endTime: end, categoryId: categoryId))
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
            if event.startTime < session.endTime && event.endTime > session.startTime {
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
        guard let id else { return "Uncategorized" }
        return categories.first(where: { $0.id == id })?.name ?? "Uncategorized"
    }

    func categoryColor(for id: UUID?) -> Color {
        guard let id,
              let hex = categories.first(where: { $0.id == id })?.colorHex,
              let color = Color(hex: hex) else {
            return .gray
        }
        return color
    }

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
        let newEvents = try await ingestionProvider.fetchIncremental(since: lastImport)
        _ = await applyImportedEventsAsync(newEvents)
    }

    @discardableResult
    func applyImportedEvents(_ newEvents: [RawEvent]) -> Int {
        var addedEvents: [RawEvent] = []

        for event in newEvents where !rawEventHashes.contains(event.metadataHash) {
            rawEvents.append(event)
            rawEventHashes.insert(event.metadataHash)
            addedEvents.append(event)
        }

        rawEvents.sort { $0.timestamp < $1.timestamp }

        var changedSessionIds: Set<UUID> = []
        if !addedEvents.isEmpty {
            changedSessionIds = SessionManager.shared.updateSessions(&sessions, with: addedEvents)
            sessions.sort { $0.startTime < $1.startTime }
        }

        if let latestScanned = newEvents.last?.timestamp {
            preferences.lastImportTimestamp = latestScanned
        }

        if !changedSessionIds.isEmpty {
            applyContextFusion(to: changedSessionIds, meetings: [])
            reevaluateSessions(sessionIds: changedSessionIds)
        }

        if !addedEvents.isEmpty || newEvents.last?.timestamp != nil {
            persist(.deferred)
        }
        return addedEvents.count
    }

    @discardableResult
    private func applyImportedEventsAsync(_ newEvents: [RawEvent]) async -> Int {
        var addedEvents: [RawEvent] = []

        for event in newEvents where !rawEventHashes.contains(event.metadataHash) {
            rawEvents.append(event)
            rawEventHashes.insert(event.metadataHash)
            addedEvents.append(event)
        }

        rawEvents.sort { $0.timestamp < $1.timestamp }

        var changedSessionIds: Set<UUID> = []
        if !addedEvents.isEmpty {
            changedSessionIds = SessionManager.shared.updateSessions(&sessions, with: addedEvents)
            sessions.sort { $0.startTime < $1.startTime }
        }

        if let latestScanned = newEvents.last?.timestamp {
            preferences.lastImportTimestamp = latestScanned
        }

        if !changedSessionIds.isEmpty {
            let meetings = await fetchMeetingContexts(for: changedSessionIds)
            applyContextFusion(to: changedSessionIds, meetings: meetings)
            reevaluateSessions(sessionIds: changedSessionIds)
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
        let sourceSessions = sessions.filter {
            $0.startTime < endDate && $0.endTime > startDate
        }

        return sourceSessions.map { session in
            var appName = session.sourceApp
            if let title = session.lastWindowTitle, !title.isEmpty {
                appName = "\(session.sourceApp) — \(title)"
            }
            return ActivityEvent(
                id: session.id,
                eventKey: "session|\(session.id.uuidString)",
                appName: appName,
                startTime: session.startTime,
                endTime: session.endTime,
                duration: session.duration,
                categoryId: session.categoryId,
                isIdle: session.isIdle,
                source: session.isIdle ? .idle : .appUsage
            )
        }
    }

    func snapshot() -> LocalData {
        configurationSnapshot()
    }

    private func sessionIds(overlapping start: Date, and end: Date) -> Set<UUID> {
        Set(sessions.filter { $0.startTime < end && $0.endTime > start }.map(\.id))
    }

    private func fetchMeetingContexts(for sessionIds: Set<UUID>) async -> [MeetingContext] {
        guard !sessionIds.isEmpty else { return [] }
        guard CalendarService.shared.hasAccess else { return [] }
        let selected = sessions.filter { sessionIds.contains($0.id) }
        guard let minStart = selected.map(\.startTime).min(),
              let maxEnd = selected.map(\.endTime).max() else {
            return []
        }
        do {
            let events = try CalendarService.shared.fetchEvents(from: minStart, to: maxEnd)
            return events.map { event in
                MeetingContext(
                    id: event.eventIdentifier,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    title: event.title
                )
            }
        } catch {
            return []
        }
    }

    private func applyContextFusion(to sessionIds: Set<UUID>, meetings: [MeetingContext]) {
        guard !sessionIds.isEmpty else { return }
        let selected = sessions.filter { sessionIds.contains($0.id) }
        let enriched = ContextFusionService.shared.enrichSessions(
            sessions: selected,
            contextEvents: contextEvents,
            meetings: meetings
        )
        let byId = Dictionary(uniqueKeysWithValues: enriched.map { ($0.id, $0) })
        for index in sessions.indices where sessionIds.contains(sessions[index].id) {
            if let updated = byId[sessions[index].id] {
                sessions[index] = updated
            }
        }
    }

    private func reevaluateAllSessions() {
        reevaluateSessions(sessionIds: Set(sessions.map(\.id)))
    }

    private func reevaluateSessions(sessionIds: Set<UUID>) {
        guard !sessionIds.isEmpty else { return }
        for index in sessions.indices where sessionIds.contains(sessions[index].id) {
            if sessions[index].isIdle {
                sessions[index].categoryId = nil
                removeRuleMatch(for: sessions[index].id)
                continue
            }

            var explicitRuleMatch: RuleMatch?
            if sessions[index].categoryId == nil,
               let match = RulesEngine.shared.evaluate(session: sessions[index], rules: rules) {
                RulesEngine.shared.apply(match: match, to: &sessions[index], using: rules)
                explicitRuleMatch = match
            }

            if sessions[index].categoryId == nil,
               let inferred = ContextFusionService.shared.suggestAutomaticCategoryName(for: sessions[index]) {
                let categoryId = addCategoryIfNeeded(name: inferred, color: AppTheme.Colors.primary)
                sessions[index].categoryId = categoryId
            }

            upsertRuleMatch(explicitRuleMatch, for: sessions[index].id)
        }
    }

    private func removeRuleMatch(for sessionId: UUID) {
        ruleMatches.removeAll { $0.sessionId == sessionId }
    }

    private func upsertRuleMatch(_ match: RuleMatch?, for sessionId: UUID) {
        removeRuleMatch(for: sessionId)
        if let match {
            ruleMatches.append(match)
            ruleMatches.sort { $0.timestamp < $1.timestamp }
        }
    }

    private func configurationSnapshot() -> LocalData {
        LocalData(
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

    private func activityStateSnapshot() -> ActivitySQLiteState {
        ActivitySQLiteState(
            rawEvents: rawEvents,
            sessions: sessions,
            ruleMatches: ruleMatches,
            contextEvents: contextEvents
        )
    }
}
