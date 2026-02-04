import Foundation
import SwiftUI

@MainActor
final class LocalDataStore: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var rules: [Rule] = []
    @Published private(set) var assignments: [String: UUID] = [:]

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
        } catch {
            categories = []
            rules = []
            assignments = [:]
            save()
        }
    }

    func save() {
        do {
            let containerURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
            let payload = LocalData(categories: categories, rules: rules, assignments: assignments)
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
            } else {
                updated.categoryId = categoryForEvent(event)
            }
            return updated
        }
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
