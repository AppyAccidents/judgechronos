import Foundation

enum AIAvailability: Equatable {
    case available
    case unavailable(String)
}

struct AISuggestion: Equatable {
    let category: String
    let rationale: String?
}

protocol AICategoryServiceType {
    var availability: AIAvailability { get }
    func suggestCategory(for event: ActivityEvent) async throws -> AISuggestion
    func suggestCategories(from events: [ActivityEvent]) async throws -> [String]
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 15, *)
final class AICategoryService: AICategoryServiceType {
    private let session: LanguageModelSession

    init() {
        session = LanguageModelSession(instructions: """
        You suggest short, helpful category names for app activity.
        Keep categories concise, 1 to 3 words.
        """)
    }

    var availability: AIAvailability {
        let status = SystemLanguageModel.default.availability
        switch status {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(String(describing: reason))
        @unknown default:
            return .unavailable("Unknown availability")
        }
    }

    func suggestCategory(for event: ActivityEvent) async throws -> AISuggestion {
        let response: LanguageModelSession.Response<CategorySuggestion> = try await session.respond(generating: CategorySuggestion.self) {
            """
            Suggest a short category (1-3 words) for this app activity.
            App: \(event.appName)
            Start: \(event.startTime.formatted(date: .omitted, time: .shortened))
            Duration minutes: \(Int(event.duration / 60))
            """
        }
        let suggestion = response.value
        return AISuggestion(category: suggestion.category, rationale: suggestion.rationale)
    }

    func suggestCategories(from events: [ActivityEvent]) async throws -> [String] {
        let appNames = Array(Set(events.map { $0.appName })).sorted().joined(separator: ", ")
        let response: LanguageModelSession.Response<CategoryList> = try await session.respond(generating: CategoryList.self) {
            """
            Propose a concise list of category names for these apps.
            Apps: \(appNames)
            """
        }
        let list = response.value
        return list.categories
    }
}

@available(macOS 15, *)
@Generable
struct CategorySuggestion {
    @Guide(description: "Short category name") var category: String
    @Guide(description: "Optional reason for the suggestion") var rationale: String?
}

@available(macOS 15, *)
@Generable
struct CategoryList {
    @Guide(description: "List of concise category names") var categories: [String]
}

#else
final class AICategoryService: AICategoryServiceType {
    var availability: AIAvailability {
        .unavailable("Foundation Models is not available on this system.")
    }

    func suggestCategory(for event: ActivityEvent) async throws -> AISuggestion {
        throw NSError(domain: "AICategoryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models is unavailable."])
    }

    func suggestCategories(from events: [ActivityEvent]) async throws -> [String] {
        throw NSError(domain: "AICategoryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Foundation Models is unavailable."])
    }
}
#endif

