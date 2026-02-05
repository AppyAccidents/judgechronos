import Testing
@testable import Judge_Chronos

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
}

final class MockAICategoryService: AICategoryServiceType {
    var availability: AIAvailability = .available
    func suggestCategory(for event: ActivityEvent) async throws -> AISuggestion {
        AISuggestion(category: "Focus", rationale: nil)
    }
    func suggestCategories(from events: [ActivityEvent]) async throws -> [String] {
        ["Focus", "Meetings"]
    }
}
