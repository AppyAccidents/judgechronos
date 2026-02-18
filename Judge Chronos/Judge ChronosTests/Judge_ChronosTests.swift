import Foundation
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

    @Test func knowledgeCReaderFetchesEventsWhenDatabaseExists() async throws {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
            .path
        guard FileManager.default.fileExists(atPath: dbPath) else { return }
        do {
            let events = try KnowledgeCReader.shared.fetchEvents(since: nil)
            #expect(events.isEmpty == false)
        } catch KnowledgeCReaderError.databaseNotFound, KnowledgeCReaderError.permissionDenied, KnowledgeCReaderError.databaseUnreadable {
            // Full Disk Access may be unavailable in test environment.
            return
        } catch KnowledgeCReaderError.queryFailed(let error) {
            if "\(error)".localizedCaseInsensitiveContains("authorization denied") {
                return
            }
            throw error
        }
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
