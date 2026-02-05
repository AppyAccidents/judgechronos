import Foundation
import SwiftUI

@MainActor
final class LocalDataStore: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var assignments: [String: UUID] = [:]
    @Published private(set) var exclusions: [ExclusionRule] = []
    @Published private(set) var focusSessions: [FocusSession] = []
    @Published private(set) var goals: [Goal] = []
    @Published var preferences: UserPreferences = .default

    private let fileURL: URL

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
            preferences = decoded.preferences
        } catch {
            categories = []
            rules = []
            assignments = [:]
            exclusions = []
            focusSessions = []
            goals = []
            preferences = .default
            save()
        }
    }

    func save() {
        do {
            let containerURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
            let payload = LocalData(
                categories: categories,
                rules: rules,
                assignments: assignments,
                exclusions: exclusions,
                focusSessions: focusSessions,
                goals: goals,
                preferences: preferences
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Keep silent to avoid crashing the app. We'll show errors in the UI when needed.
        }
    }

    func addCategory(name: String, color: Color) {
        let newCategory = Category(id: UUID(), name: name, colorHex: color.toHex())
        categories.append(newCategory)
        save()
    }

    func updateCategory(_ category: Category, name: String, color: Color) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index].name = name
        categories[index].colorHex = color.toHex()
        save()
    }

    func deleteCategory(_ category: Category) {
        categories.removeAll { $0.id == category.id }
        rules.removeAll { $0.categoryId == category.id }
        assignments = assignments.filter { $0.value != category.id }
        save()
    }

    func addRule(pattern: String, categoryId: UUID) {
        let rule = Rule(id: UUID(), pattern: pattern, categoryId: categoryId)
        rules.append(rule)
        save()
    }

    func deleteRule(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func addExclusion(pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let rule = ExclusionRule(id: UUID(), pattern: trimmed)
        exclusions.append(rule)
        save()
    }

    func deleteExclusion(_ rule: ExclusionRule) {
        exclusions.removeAll { $0.id == rule.id }
        save()
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
        save()
    }

    func assignCategory(eventKey: String, categoryId: UUID?) {
        if let categoryId = categoryId {
            assignments[eventKey] = categoryId
        } else {
            assignments.removeValue(forKey: eventKey)
        }
        save()
    }

    func categoryForEvent(_ event: ActivityEvent) -> UUID? {
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

    func addCategoryIfNeeded(name: String, color: Color = .blue) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = categoryId(named: trimmed) {
            return existing
        }
        let newCategory = Category(id: UUID(), name: trimmed, colorHex: color.toHex())
        categories.append(newCategory)
        save()
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
        save()
    }

    func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        save()
    }

    func startFocusSession(durationMinutes: Int, categoryId: UUID) {
        let start = Date()
        let end = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: start) ?? start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let session = FocusSession(id: UUID(), startTime: start, endTime: end, categoryId: categoryId)
        focusSessions.append(session)
        save()
    }

    func endActiveFocusSession() {
        guard let index = activeFocusSessionIndex() else { return }
        focusSessions[index].endTime = Date()
        save()
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
        save()
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
}
