import Foundation
import SQLite3
import Testing
@testable import Judge_Chronos

@MainActor
struct Judge_ChronosTests {

    @Test func macAbsoluteConversion() async throws {
        let date = ActivityDatabase.macAbsoluteToDate(0)
        #expect(Int(date.timeIntervalSince1970) == Int(ActivityDatabase.macAbsoluteTimeIntervalSince1970))
    }

    @Test func durationFormatting() async throws {
        let formatted = Formatting.formatDuration(125)
        #expect(formatted == "2m 05s")
    }

    @Test func idleInsertion() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = LocalDataStore(fileURL: tempURL)
        let viewModel = ActivityViewModel(dataStore: store)
        let start = Date()
        let first = ActivityEvent(
            id: UUID(),
            eventKey: ActivityEventKey.make(appName: "AppA", startTime: start, endTime: start.addingTimeInterval(60)),
            appName: "AppA",
            startTime: start,
            endTime: start.addingTimeInterval(60),
            duration: 60,
            categoryId: nil,
            isIdle: false,
            source: .appUsage
        )
        let second = ActivityEvent(
            id: UUID(),
            eventKey: ActivityEventKey.make(appName: "AppB", startTime: start.addingTimeInterval(600), endTime: start.addingTimeInterval(900)),
            appName: "AppB",
            startTime: start.addingTimeInterval(600),
            endTime: start.addingTimeInterval(900),
            duration: 300,
            categoryId: nil,
            isIdle: false,
            source: .appUsage
        )
        let output = viewModel.insertIdleEvents(into: [first, second])
        #expect(output.count == 3)
        #expect(output[1].isIdle == true)
    }

    @Test func applySuggestionCreatesCategory() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = LocalDataStore(fileURL: tempURL)
        let viewModel = ActivityViewModel(dataStore: store, aiService: MockAICategoryService())
        let start = Date()
        let event = ActivityEvent(
            id: UUID(),
            eventKey: ActivityEventKey.make(appName: "AppA", startTime: start, endTime: start.addingTimeInterval(60)),
            appName: "AppA",
            startTime: start,
            endTime: start.addingTimeInterval(60),
            duration: 60,
            categoryId: nil,
            isIdle: false,
            source: .appUsage
        )
        viewModel.suggestions[event.eventKey] = AISuggestion(category: "Focus", rationale: nil)
        viewModel.applySuggestion(for: event)
        #expect(store.categories.contains(where: { $0.name == "Focus" }))
        #expect(store.assignmentForEvent(event) != nil)
    }

    @Test func knowledgeCTimestampDecodingSupportsNumericTypes() async throws {
        #expect(KnowledgeCReader.toTimeInterval(123.5) == 123.5)
        #expect(KnowledgeCReader.toTimeInterval(Int64(124)) == 124.0)
        #expect(KnowledgeCReader.toTimeInterval(125) == 125.0)
        #expect(KnowledgeCReader.toTimeInterval(NSNumber(value: 126)) == 126.0)
    }

    @Test func knowledgeCReaderFetchesEventsFromFixtureDatabase() async throws {
        let dbURL = try makeKnowledgeCFixtureDatabase()
        let lastImport = Date(timeIntervalSince1970: 1_700_000_000)
        let events = try KnowledgeCReader.shared.fetchEvents(since: lastImport, databasePath: dbURL.path, searchedPaths: [dbURL.path])
        #expect(events.count == 1)
        #expect(events.first?.appName == "Visual Studio Code")
        #expect((events.first?.duration ?? 0) > 0)
    }

    @Test func watermarkAdvancesWhenAllImportedRowsAreDuplicates() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = LocalDataStore(fileURL: tempURL)
        let start = Date()
        let existing = RawEvent(
            id: UUID(),
            timestamp: start,
            duration: 60,
            bundleId: "com.example.app",
            appName: "Example",
            windowTitle: nil,
            source: .appUsage,
            metadataHash: "hash-1",
            importedAt: start
        )
        store.addRawEvent(existing)
        let later = start.addingTimeInterval(3600)
        let duplicateRow = RawEvent(
            id: UUID(),
            timestamp: later,
            duration: 60,
            bundleId: "com.example.app",
            appName: "Example",
            windowTitle: nil,
            source: .appUsage,
            metadataHash: "hash-1",
            importedAt: later
        )

        let addedCount = store.applyImportedEvents([duplicateRow])

        #expect(addedCount == 0)
        #expect(store.preferences.lastImportTimestamp == later)
    }

    @Test func contextEventsAreCappedAtRetentionLimit() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = LocalDataStore(fileURL: tempURL)
        for i in 0..<2105 {
            let event = ContextEvent(
                id: UUID(),
                timestamp: Date().addingTimeInterval(TimeInterval(i)),
                bundleId: "com.example.app",
                appName: "Example",
                windowTitle: "Window \(i)",
                documentPath: nil
            )
            store.addContextEvent(event)
        }
        #expect(store.contextEvents.count == 2000)
    }

    @Test func accessibilityReaderCooldownDeduplicatesContext() async throws {
        let reader = AccessibilityReader()
        let now = Date()
        let first = reader.shouldRecordAndMarkContext(appName: "Safari", windowTitle: "Doc", now: now)
        let second = reader.shouldRecordAndMarkContext(appName: "Safari", windowTitle: "Doc", now: now.addingTimeInterval(5))
        let third = reader.shouldRecordAndMarkContext(appName: "Safari", windowTitle: "Doc", now: now.addingTimeInterval(25))

        #expect(first == true)
        #expect(second == false)
        #expect(third == true)
    }

    @Test func contextFusionAppliesMeetingAndWindowContext() async throws {
        let start = Date()
        let session = Session(
            id: UUID(),
            startTime: start,
            endTime: start.addingTimeInterval(600),
            sourceApp: "Visual Studio Code",
            rawEventIds: [],
            isIdle: false
        )
        let contextEvents = [
            ContextEvent(
                id: UUID(),
                timestamp: start.addingTimeInterval(120),
                bundleId: "com.microsoft.VSCode",
                appName: "Visual Studio Code",
                windowTitle: "Jira ticket ABC-123",
                documentPath: nil
            )
        ]
        let meetings = [
            MeetingContext(
                id: "meeting-1",
                startDate: start.addingTimeInterval(60),
                endDate: start.addingTimeInterval(300),
                title: "Daily Standup"
            )
        ]

        let enriched = ContextFusionService.shared.enrichSessions(sessions: [session], contextEvents: contextEvents, meetings: meetings)
        #expect(enriched.count == 1)
        #expect(enriched[0].bundleId == "com.microsoft.VSCode")
        #expect(enriched[0].lastWindowTitle == "Jira ticket ABC-123")
        #expect(enriched[0].overlappingMeetingIds == ["meeting-1"])
        #expect(enriched[0].inferenceConfidence > 0.5)
    }

    @Test func contextFusionSuggestsExpectedCategoryFromJiraAndTerminal() async throws {
        let now = Date()
        let jiraSession = Session(
            id: UUID(),
            startTime: now,
            endTime: now.addingTimeInterval(300),
            sourceApp: "Google Chrome",
            bundleId: "com.google.Chrome",
            lastWindowTitle: "Jira - Sprint Board",
            windowTitleSamples: ["Jira - Sprint Board"],
            rawEventIds: [],
            isIdle: false
        )
        let terminalSession = Session(
            id: UUID(),
            startTime: now,
            endTime: now.addingTimeInterval(300),
            sourceApp: "Ghostty",
            bundleId: "com.mitchellh.ghostty",
            rawEventIds: [],
            isIdle: false
        )

        #expect(ContextFusionService.shared.suggestAutomaticCategoryName(for: jiraSession) == "Project Management")
        #expect(ContextFusionService.shared.suggestAutomaticCategoryName(for: terminalSession) == "Development")
    }

    @Test func ruleMatcherHonorsPriorityAndWindowTitle() async throws {
        let session = Session(
            id: UUID(),
            startTime: Date(),
            endTime: Date().addingTimeInterval(900),
            sourceApp: "Google Chrome",
            bundleId: "com.google.Chrome",
            lastWindowTitle: "Jira ABC-123 planning",
            windowTitleSamples: ["Jira ABC-123 planning"],
            rawEventIds: [],
            isIdle: false
        )

        let low = Rule(
            id: UUID(),
            name: "Generic Chrome",
            priority: 5,
            isEnabled: true,
            bundleIdPattern: "chrome",
            appNamePattern: "Chrome",
            windowTitlePattern: nil,
            minDuration: nil,
            targetProjectId: nil,
            targetCategoryId: UUID(),
            targetTagIds: [],
            markAsPrivate: false
        )
        let high = Rule(
            id: UUID(),
            name: "Jira Work",
            priority: 20,
            isEnabled: true,
            bundleIdPattern: nil,
            appNamePattern: "Chrome",
            windowTitlePattern: "jira",
            minDuration: 60,
            targetProjectId: nil,
            targetCategoryId: UUID(),
            targetTagIds: [],
            markAsPrivate: false
        )

        let evaluation = RuleMatcher.shared.evaluate(session: session, rules: [low, high])
        #expect(evaluation?.rule.id == high.id)
    }

    @Test func localDataStoreAppliesAutomaticCategoryForContextualSessions() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let store = LocalDataStore(fileURL: tempURL)
        let start = Date()
        let raw = RawEvent(
            id: UUID(),
            timestamp: start,
            duration: 300,
            bundleId: "com.google.Chrome",
            appName: "Google Chrome",
            windowTitle: nil,
            source: .appUsage,
            metadataHash: UUID().uuidString,
            importedAt: start
        )
        store.addRawEvent(raw)
        store.addContextEvent(
            ContextEvent(
                id: UUID(),
                timestamp: start.addingTimeInterval(20),
                bundleId: "com.google.Chrome",
                appName: "Google Chrome",
                windowTitle: "Jira - Sprint planning",
                documentPath: nil
            )
        )

        let dayEvents = store.events(from: start.addingTimeInterval(-60), to: start.addingTimeInterval(600))
        let categorized = store.applyCategories(to: dayEvents)
        let categoryNames = Set(categorized.compactMap { store.categoryName(for: $0.categoryId) })
        #expect(categoryNames.contains("Project Management") || categoryNames.contains("Development"))
    }

    @Test func localDataStoreUsesInjectedIngestionProvider() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let start = Date()
        let provider = MockIngestionProvider(events: [
            RawEvent(
                id: UUID(),
                timestamp: start,
                duration: 120,
                bundleId: "com.microsoft.VSCode",
                appName: "Visual Studio Code",
                windowTitle: "feature.swift",
                source: .appUsage,
                metadataHash: UUID().uuidString,
                importedAt: start
            )
        ])
        let store = LocalDataStore(
            fileURL: tempURL,
            channel: .macAppStore,
            ingestionProvider: provider
        )

        try await store.performIncrementalImport()

        #expect(store.activityCapabilities.supportsHistoricalImport == false)
        #expect(store.rawEvents.isEmpty == false)
        #expect(store.sessions.isEmpty == false)
    }

    private func makeKnowledgeCFixtureDatabase() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("knowledgec-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "JudgeChronosTests", code: 1)
        }
        defer { sqlite3_close(db) }

        let create = """
        CREATE TABLE ZOBJECT (
            ZVALUESTRING TEXT,
            ZSTARTDATE REAL,
            ZENDDATE REAL,
            ZSTREAMNAME TEXT
        );
        """
        guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "JudgeChronosTests", code: 2)
        }

        let base = Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSince1970 - KnowledgeCReader.macAbsoluteTimeIntervalSince1970
        let insert = """
        INSERT INTO ZOBJECT (ZVALUESTRING, ZSTARTDATE, ZENDDATE, ZSTREAMNAME)
        VALUES ('Visual Studio Code', \(base + 600), \(base + 900), '/app/usage'),
               ('Terminal', \(base - 600), \(base - 300), '/app/usage');
        """
        guard sqlite3_exec(db, insert, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "JudgeChronosTests", code: 3)
        }
        return url
    }
}

final class MockAICategoryService: AICategoryServiceType {
    var availability: AIAvailability = .available
    func refreshAvailability() async -> AIAvailability { availability }
    func suggestCategory(for event: ActivityEvent) async throws -> AISuggestion {
        AISuggestion(category: "Focus", rationale: nil)
    }
    func suggestCategories(from events: [ActivityEvent]) async throws -> [String] {
        ["Focus", "Meetings"]
    }
}

@MainActor
final class MockIngestionProvider: ActivityIngestionProvider {
    let capabilities = ActivityCapabilities(supportsHistoricalImport: false, requiresFullDiskAccess: false)
    private let events: [RawEvent]

    init(events: [RawEvent]) {
        self.events = events
    }

    func fetchIncremental(since lastImport: Date?) async throws -> [RawEvent] {
        events
    }
}
