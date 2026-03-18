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

    @Published private(set) var clients: [Client] = []
    @Published private(set) var activities: [Activity] = []
    @Published private(set) var manualTimers: [ManualTimer] = []
    @Published private(set) var invoices: [Invoice] = []
    @Published private(set) var favorites: [Favorite] = []

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
    
    // MARK: - Performance: Dictionary-based indices for O(1) lookups
    private var sessionById: [UUID: Session] = [:]
    private var projectById: [UUID: Project] = [:]
    private var categoryById: [UUID: Category] = [:]
    private var categoryNameIndex: [String: UUID] = [:]
    private var sessionsByDate: [Date: [Session]] = [:]
    private var clientById: [UUID: Client] = [:]
    private var activityById: [UUID: Activity] = [:]
    private var invoiceById: [UUID: Invoice] = [:]

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
        clients = decoded?.clients ?? []
        activities = decoded?.activities ?? []
        manualTimers = decoded?.manualTimers ?? []
        invoices = decoded?.invoices ?? []
        favorites = decoded?.favorites ?? []

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
        
        // Build lookup indices for performance
        rebuildIndices()

        if decoded == nil {
            persist(.immediate)
        } else {
            persist(.deferred)
        }
    }
    
    // MARK: - Index Management
    private func rebuildIndices() {
        // Session index by ID
        sessionById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        
        // Project index by ID
        projectById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        
        // Category index by ID
        categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        
        // Category name index (lowercase for case-insensitive lookup)
        categoryNameIndex = [:]
        for category in categories {
            let key = category.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            categoryNameIndex[key] = category.id
        }
        
        // Sessions by date (start of day)
        rebuildSessionsByDate()

        // New entity indices
        clientById = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
        activityById = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        invoiceById = Dictionary(uniqueKeysWithValues: invoices.map { ($0.id, $0) })
    }
    
    private func rebuildSessionsByDate() {
        sessionsByDate = [:]
        let calendar = Calendar.current
        for session in sessions {
            let day = calendar.startOfDay(for: session.startTime)
            sessionsByDate[day, default: []].append(session)
        }
    }
    
    private func rebuildSessionIndices() {
        // Session index by ID
        sessionById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        // Session by date
        rebuildSessionsByDate()
    }
    
    // MARK: - Index Incremental Updates
    private func indexAdd(session: Session) {
        sessionById[session.id] = session
        let day = Calendar.current.startOfDay(for: session.startTime)
        sessionsByDate[day, default: []].append(session)
    }
    
    private func indexUpdate(session: Session) {
        // If date changed, need to rebuild date index
        if let old = sessionById[session.id], 
           !Calendar.current.isDate(old.startTime, inSameDayAs: session.startTime) {
            sessionById[session.id] = session
            rebuildSessionsByDate()
        } else {
            sessionById[session.id] = session
            // Update in date index
            let day = Calendar.current.startOfDay(for: session.startTime)
            if let index = sessionsByDate[day]?.firstIndex(where: { $0.id == session.id }) {
                sessionsByDate[day]?[index] = session
            }
        }
    }
    
    private func indexRemove(sessionId: UUID) {
        guard let session = sessionById.removeValue(forKey: sessionId) else { return }
        let day = Calendar.current.startOfDay(for: session.startTime)
        sessionsByDate[day]?.removeAll { $0.id == sessionId }
    }
    
    private func indexAdd(project: Project) {
        projectById[project.id] = project
    }
    
    private func indexUpdate(project: Project) {
        projectById[project.id] = project
    }
    
    private func indexRemove(projectId: UUID) {
        projectById.removeValue(forKey: projectId)
    }
    
    private func indexAdd(category: Category) {
        categoryById[category.id] = category
        let key = category.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        categoryNameIndex[key] = category.id
    }
    
    private func indexUpdate(category: Category) {
        // Update category ID index
        categoryById[category.id] = category
        // Rebuild name index since name might have changed
        categoryNameIndex = [:]
        for cat in categories {
            let key = cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            categoryNameIndex[key] = cat.id
        }
    }
    
    private func indexRemove(categoryId: UUID) {
        categoryById.removeValue(forKey: categoryId)
        categoryNameIndex = categoryNameIndex.filter { $0.value != categoryId }
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
        indexAdd(category: newCategory)
        persist(.immediate)
    }

    func updateCategory(_ category: Category, name: String, color: Color) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index].name = name
        categories[index].colorHex = color.toHex()
        indexUpdate(category: categories[index])
        persist(.immediate)
    }

    func deleteCategory(_ category: Category) {
        categories.removeAll { $0.id == category.id }
        rules.removeAll { $0.targetCategoryId == category.id }
        assignments = assignments.filter { $0.value != category.id }
        indexRemove(categoryId: category.id)
        persist(.immediate)
    }

    // MARK: - Project Management
    
    func addProject(_ project: Project) {
        projects.append(project)
        indexAdd(project: project)
        persist(.immediate)
    }
    
    func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        indexUpdate(project: project)
        persist(.immediate)
    }
    
    func deleteProject(_ project: Project) {
        // Reassign children to root (no parent)
        for index in projects.indices where projects[index].parentId == project.id {
            projects[index].parentId = nil
            indexUpdate(project: projects[index])
        }
        projects.removeAll { $0.id == project.id }
        indexRemove(projectId: project.id)
        // Clear project assignments and update session indices
        for index in sessions.indices where sessions[index].projectId == project.id {
            sessions[index].projectId = nil
            indexUpdate(session: sessions[index])
        }
        persist(.immediate)
    }
    
    func moveProject(_ projectId: UUID, toParent parentId: UUID?) {
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        // Prevent circular references
        if let parentId = parentId {
            guard !isDescendant(projectId: parentId, of: projectId) else { return }
        }
        projects[index].parentId = parentId
        indexUpdate(project: projects[index])
        persist(.immediate)
    }
    
    func projectHierarchy() -> [ProjectNode] {
        buildProjectTree(parentId: nil, level: 0)
    }
    
    func projectPath(for projectId: UUID) -> [Project] {
        var path: [Project] = []
        var currentId: UUID? = projectId
        while let id = currentId, let project = projectById[id] {
            path.insert(project, at: 0)
            currentId = project.parentId
        }
        return path
    }
    
    func totalTime(for projectId: UUID, includeSubprojects: Bool = true) -> TimeInterval {
        var projectIds = [projectId]
        if includeSubprojects {
            projectIds.append(contentsOf: descendantProjectIds(of: projectId))
        }
        return sessions
            .filter { session in
                projectIds.contains { $0 == session.projectId }
            }
            .reduce(0) { $0 + $1.duration }
    }
    
    func assignProject(appName: String, projectId: UUID?) {
        if let projectId {
            assignments[appName] = projectId
        } else {
            assignments.removeValue(forKey: appName)
        }
        persist(.immediate)
    }
    
    // MARK: - Project Helpers
    
    private func buildProjectTree(parentId: UUID?, level: Int) -> [ProjectNode] {
        projects
            .filter { $0.parentId == parentId && !$0.archived }
            .sorted { $0.createdAt < $1.createdAt }
            .map { project in
                ProjectNode(
                    id: project.id,
                    project: project,
                    children: buildProjectTree(parentId: project.id, level: level + 1),
                    level: level,
                    isExpanded: true
                )
            }
    }
    
    private func isDescendant(projectId: UUID, of ancestorId: UUID) -> Bool {
        let children = projects.filter { $0.parentId == ancestorId }
        for child in children {
            if child.id == projectId || isDescendant(projectId: projectId, of: child.id) {
                return true
            }
        }
        return false
    }
    
    func descendantProjectIds(of projectId: UUID) -> [UUID] {
        let children = projects.filter { $0.parentId == projectId }
        var ids = children.map { $0.id }
        for child in children {
            ids.append(contentsOf: descendantProjectIds(of: child.id))
        }
        return ids
    }
    
    func projectName(for projectId: UUID?) -> String {
        guard let projectId else { return "Uncategorized" }
        return projectById[projectId]?.name ?? "Uncategorized"
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

    func addSession(_ session: Session) {
        sessions.append(session)
        sessions.sort { $0.startTime < $1.startTime }
        indexAdd(session: session)
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
        rebuildSessionIndices()
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
        // O(1) lookup using dictionary index
        if let session = sessionById[event.id], let explicit = session.categoryId {
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
        if let session = sessionById[event.id],
           let rule = RuleMatcher.shared.evaluate(session: session, rules: rules) {
            return rule.rule.targetCategoryId
        }
        return nil
    }

    func assignmentForEvent(_ event: ActivityEvent) -> UUID? {
        // O(1) lookup using dictionary index
        if let session = sessionById[event.id] {
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
        return categoryNameIndex[normalized]
    }

    func addCategoryIfNeeded(name: String, color: Color = AppTheme.Colors.primary) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = categoryId(named: trimmed) {
            return existing
        }
        let newCategory = Category(id: UUID(), name: trimmed, colorHex: color.toHex())
        categories.append(newCategory)
        indexAdd(category: newCategory)
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
        return categoryById[id]?.name ?? "Uncategorized"
    }

    func categoryColor(for id: UUID?) -> Color {
        guard let id,
              let hex = categoryById[id]?.colorHex,
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
            rebuildSessionIndices()
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
            rebuildSessionIndices()
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

    func updateSessionActivity(sessionId: UUID, activityId: UUID?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].activityId = activityId
        indexUpdate(session: sessions[index])
        persist(.immediate)
    }

    func updateSessionBreak(sessionId: UUID, isBreak: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].isBreak = isBreak
        indexUpdate(session: sessions[index])
        persist(.immediate)
    }

    func updateSessionCategory(sessionId: UUID, categoryId: UUID?) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].categoryId = categoryId
        indexUpdate(session: sessions[index])
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
        var updatedSessionIds: Set<UUID> = []
        for index in sessions.indices where sessionIds.contains(sessions[index].id) {
            if sessions[index].isIdle {
                sessions[index].categoryId = nil
                removeRuleMatch(for: sessions[index].id)
                updatedSessionIds.insert(sessions[index].id)
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
            updatedSessionIds.insert(sessions[index].id)
        }
        // Update indices for modified sessions
        for sessionId in updatedSessionIds {
            if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                indexUpdate(session: sessions[index])
            }
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

    // MARK: - Client Management

    func addClient(_ client: Client) {
        clients.append(client)
        clientById[client.id] = client
        persist(.immediate)
    }

    func updateClient(_ client: Client) {
        guard let index = clients.firstIndex(where: { $0.id == client.id }) else { return }
        clients[index] = client
        clientById[client.id] = client
        persist(.immediate)
    }

    func deleteClient(_ client: Client) {
        clients.removeAll { $0.id == client.id }
        clientById.removeValue(forKey: client.id)
        for index in projects.indices where projects[index].clientId == client.id {
            projects[index].clientId = nil
            indexUpdate(project: projects[index])
        }
        persist(.immediate)
    }

    func clientName(for clientId: UUID?) -> String {
        guard let clientId else { return "No Client" }
        return clientById[clientId]?.name ?? "No Client"
    }

    // MARK: - Activity Management

    func addActivity(_ activity: Activity) {
        activities.append(activity)
        activityById[activity.id] = activity
        persist(.immediate)
    }

    func updateActivity(_ activity: Activity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[index] = activity
        activityById[activity.id] = activity
        persist(.immediate)
    }

    func deleteActivity(_ activity: Activity) {
        activities.removeAll { $0.id == activity.id }
        activityById.removeValue(forKey: activity.id)
        for index in sessions.indices where sessions[index].activityId == activity.id {
            sessions[index].activityId = nil
            indexUpdate(session: sessions[index])
        }
        persist(.immediate)
    }

    func activitiesForProject(_ projectId: UUID?) -> [Activity] {
        activities.filter { $0.projectId == projectId || $0.projectId == nil }
    }

    func activityName(for activityId: UUID?) -> String {
        guard let activityId else { return "No Activity" }
        return activityById[activityId]?.name ?? "No Activity"
    }

    // MARK: - Manual Timer Management

    func addManualTimer(_ timer: ManualTimer) {
        manualTimers.append(timer)
        persist(.immediate)
    }

    func updateManualTimer(_ timer: ManualTimer) {
        guard let index = manualTimers.firstIndex(where: { $0.id == timer.id }) else { return }
        manualTimers[index] = timer
        persist(.immediate)
    }

    func stopManualTimer(id: UUID) {
        guard let index = manualTimers.firstIndex(where: { $0.id == id }) else { return }
        manualTimers[index].stoppedAt = Date()
        let timer = manualTimers[index]
        let session = Session(
            id: UUID(),
            startTime: timer.startedAt,
            endTime: timer.stoppedAt ?? Date(),
            sourceApp: timer.description ?? "Manual Timer",
            rawEventIds: [],
            projectId: timer.projectId,
            categoryId: nil,
            tagIds: timer.tagIds,
            isIdle: false,
            activityId: timer.activityId
        )
        addSession(session)
        persist(.immediate)
    }

    func deleteManualTimer(_ timer: ManualTimer) {
        manualTimers.removeAll { $0.id == timer.id }
        persist(.immediate)
    }

    var activeTimers: [ManualTimer] {
        manualTimers.filter { $0.isRunning }
    }

    // MARK: - Invoice Management

    func addInvoice(_ invoice: Invoice) {
        invoices.append(invoice)
        invoiceById[invoice.id] = invoice
        persist(.immediate)
    }

    func updateInvoice(_ invoice: Invoice) {
        guard let index = invoices.firstIndex(where: { $0.id == invoice.id }) else { return }
        invoices[index] = invoice
        invoiceById[invoice.id] = invoice
        persist(.immediate)
    }

    func deleteInvoice(_ invoice: Invoice) {
        invoices.removeAll { $0.id == invoice.id }
        invoiceById.removeValue(forKey: invoice.id)
        persist(.immediate)
    }

    func nextInvoiceNumber() -> String {
        let number = preferences.nextInvoiceNumber
        let formatted = "\(preferences.invoiceNumberPrefix)\(String(format: "%04d", number))"
        updatePreferences { $0.nextInvoiceNumber += 1 }
        return formatted
    }

    // MARK: - Favorites Management

    func addFavorite(_ favorite: Favorite) {
        favorites.append(favorite)
        persist(.immediate)
    }

    func updateFavorite(_ favorite: Favorite) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
        favorites[index] = favorite
        persist(.immediate)
    }

    func deleteFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        persist(.immediate)
    }

    func reorderFavorites(_ newOrder: [Favorite]) {
        favorites = newOrder
        persist(.immediate)
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
            contextEvents: contextEvents,
            clients: clients,
            activities: activities,
            manualTimers: manualTimers,
            invoices: invoices,
            favorites: favorites
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
