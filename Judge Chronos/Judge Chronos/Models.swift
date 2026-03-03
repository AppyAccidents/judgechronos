import AppKit
import Foundation
import SwiftUI

enum ActivityEventSource: String, Codable, Hashable {
    case appUsage
    case calendar
    case idle
}

struct RawEvent: Identifiable, Hashable, Codable {
    let id: UUID
    let timestamp: Date
    let duration: TimeInterval
    let bundleId: String?
    let appName: String
    let windowTitle: String?
    let source: ActivityEventSource
    let metadataHash: String
    let importedAt: Date
}

struct Session: Identifiable, Hashable, Codable {
    let id: UUID
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
    var sourceApp: String
    var bundleId: String?
    var lastWindowTitle: String?
    var windowTitleSamples: [String]
    var overlappingMeetingIds: [String]
    var rawEventIds: [UUID]
    var projectId: UUID?
    var inferredProjectId: UUID?
    var inferenceConfidence: Double
    var categoryId: UUID?
    var tagIds: Set<UUID>
    var note: String?
    var isPrivate: Bool
    var isIdle: Bool

    init(
        id: UUID,
        startTime: Date,
        endTime: Date,
        sourceApp: String,
        bundleId: String? = nil,
        lastWindowTitle: String? = nil,
        windowTitleSamples: [String] = [],
        overlappingMeetingIds: [String] = [],
        rawEventIds: [UUID],
        projectId: UUID? = nil,
        inferredProjectId: UUID? = nil,
        inferenceConfidence: Double = 0,
        categoryId: UUID? = nil,
        tagIds: Set<UUID> = [],
        note: String? = nil,
        isPrivate: Bool = false,
        isIdle: Bool
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.sourceApp = sourceApp
        self.bundleId = bundleId
        self.lastWindowTitle = lastWindowTitle
        self.windowTitleSamples = windowTitleSamples
        self.overlappingMeetingIds = overlappingMeetingIds
        self.rawEventIds = rawEventIds
        self.projectId = projectId
        self.inferredProjectId = inferredProjectId
        self.inferenceConfidence = inferenceConfidence
        self.categoryId = categoryId
        self.tagIds = tagIds
        self.note = note
        self.isPrivate = isPrivate
        self.isIdle = isIdle
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startTime
        case endTime
        case sourceApp
        case bundleId
        case lastWindowTitle
        case windowTitleSamples
        case overlappingMeetingIds
        case rawEventIds
        case projectId
        case inferredProjectId
        case inferenceConfidence
        case categoryId
        case tagIds
        case note
        case isPrivate
        case isIdle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        sourceApp = try container.decode(String.self, forKey: .sourceApp)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        lastWindowTitle = try container.decodeIfPresent(String.self, forKey: .lastWindowTitle)
        windowTitleSamples = try container.decodeIfPresent([String].self, forKey: .windowTitleSamples) ?? []
        overlappingMeetingIds = try container.decodeIfPresent([String].self, forKey: .overlappingMeetingIds) ?? []
        rawEventIds = try container.decodeIfPresent([UUID].self, forKey: .rawEventIds) ?? []
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        inferredProjectId = try container.decodeIfPresent(UUID.self, forKey: .inferredProjectId)
        inferenceConfidence = try container.decodeIfPresent(Double.self, forKey: .inferenceConfidence) ?? 0
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        tagIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .tagIds) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        isIdle = try container.decodeIfPresent(Bool.self, forKey: .isIdle) ?? false
    }
}

enum ProductivityRating: Int, Codable, CaseIterable {
    case veryDistracting = -2
    case distracting = -1
    case neutral = 0
    case productive = 1
    case veryProductive = 2
    
    var label: String {
        switch self {
        case .veryDistracting: return "Very Distracting"
        case .distracting: return "Distracting"
        case .neutral: return "Neutral"
        case .productive: return "Productive"
        case .veryProductive: return "Very Productive"
        }
    }
    
    var color: Color {
        switch self {
        case .veryDistracting: return .red
        case .distracting: return .orange
        case .neutral: return .gray
        case .productive: return .green
        case .veryProductive: return Color(hex: "#22C55E") ?? .green
        }
    }
    
    var icon: String {
        switch self {
        case .veryDistracting: return "arrow.down.circle.fill"
        case .distracting: return "arrow.down"
        case .neutral: return "minus"
        case .productive: return "arrow.up"
        case .veryProductive: return "arrow.up.circle.fill"
        }
    }
}

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var parentId: UUID?
    var productivityRating: ProductivityRating?
    var hourlyRate: Double?
    var isBillable: Bool
    var archived: Bool
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        parentId: UUID? = nil,
        productivityRating: ProductivityRating? = nil,
        hourlyRate: Double? = nil,
        isBillable: Bool = false,
        archived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.parentId = parentId
        self.productivityRating = productivityRating
        self.hourlyRate = hourlyRate
        self.isBillable = isBillable
        self.archived = archived
        self.createdAt = createdAt
    }
}

struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
}

struct RuleMatch: Identifiable, Codable, Hashable {
    let id: UUID
    let ruleId: UUID
    let sessionId: UUID
    let timestamp: Date
    let appliedChanges: String // JSON or description of what changed
}

struct ActivityEvent: Identifiable, Hashable {
    let id: UUID
    let eventKey: String
    let appName: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    var categoryId: UUID?
    let isIdle: Bool
    let source: ActivityEventSource
}

struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
}

struct Rule: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String // Description of the rule
    var priority: Int
    var isEnabled: Bool
    
    // Conditions
    var bundleIdPattern: String?
    var appNamePattern: String?
    var windowTitlePattern: String?
    var minDuration: TimeInterval?
    
    // Actions
    var targetProjectId: UUID?
    var targetCategoryId: UUID?
    var targetTagIds: Set<UUID>
    var markAsPrivate: Bool
    
    // Legacy support for pattern match in RulesView
    var pattern: String { appNamePattern ?? "" }
}

struct ExclusionRule: Identifiable, Codable, Hashable {
    let id: UUID
    var pattern: String
}

struct FocusSession: Identifiable, Codable, Hashable {
    let id: UUID
    var startTime: Date
    var endTime: Date
    var categoryId: UUID
}

struct Goal: Identifiable, Codable, Hashable {
    let id: UUID
    var categoryId: UUID
    var minutesPerDay: Int
}

struct UserPreferences: Codable, Hashable {
    var hasCompletedOnboarding: Bool
    var workDayStart: String
    var workDayEnd: String
    var privateModeEnabled: Bool
    var reviewReminderEnabled: Bool
    var reviewReminderTime: String
    var weeklyRecapEnabled: Bool
    var goalNudgesEnabled: Bool
    var emailSummaryEnabled: Bool
    var calendarIntegrationEnabled: Bool
    var iCloudBackupEnabled: Bool
    
    // Phase 1: Incremental Import State
    var lastImportTimestamp: Date?
    var lastImportHash: String?

    static let `default` = UserPreferences(
        hasCompletedOnboarding: false,
        workDayStart: "09:00",
        workDayEnd: "17:00",
        privateModeEnabled: false,
        reviewReminderEnabled: false,
        reviewReminderTime: "17:30",
        weeklyRecapEnabled: true,
        goalNudgesEnabled: false,
        emailSummaryEnabled: false,
        calendarIntegrationEnabled: true,
        iCloudBackupEnabled: false,
        lastImportTimestamp: nil,
        lastImportHash: nil
    )
}

struct LocalData: Codable {
    var categories: [Category]
    var rules: [Rule]
    var assignments: [String: UUID]
    var exclusions: [ExclusionRule]
    var focusSessions: [FocusSession]
    var goals: [Goal]
    var preferences: UserPreferences
    
    // Phase 0: New Data Models
    var rawEvents: [RawEvent] = []
    var sessions: [Session] = []
    var projects: [Project] = []
    var tags: [Tag] = []
    var ruleMatches: [RuleMatch] = []
    var contextEvents: [ContextEvent] = []

    // Transient migration payloads from old JSON versions.
    private(set) var migratedRawEvents: [RawEvent] = []
    private(set) var migratedSessions: [Session] = []
    private(set) var migratedRuleMatches: [RuleMatch] = []
    private(set) var migratedContextEvents: [ContextEvent] = []

    enum CodingKeys: String, CodingKey {
        case categories
        case rules
        case assignments
        case exclusions
        case focusSessions
        case goals
        case preferences
        case rawEvents
        case sessions
        case projects
        case tags
        case ruleMatches
        case contextEvents
    }

    init(
        categories: [Category] = [],
        rules: [Rule] = [],
        assignments: [String: UUID] = [:],
        exclusions: [ExclusionRule] = [],
        focusSessions: [FocusSession] = [],
        goals: [Goal] = [],
        preferences: UserPreferences = .default,
        rawEvents: [RawEvent] = [],
        sessions: [Session] = [],
        projects: [Project] = [],
        tags: [Tag] = [],
        ruleMatches: [RuleMatch] = [],
        contextEvents: [ContextEvent] = []
    ) {
        self.categories = categories
        self.rules = rules
        self.assignments = assignments
        self.exclusions = exclusions
        self.focusSessions = focusSessions
        self.goals = goals
        self.preferences = preferences
        self.rawEvents = rawEvents
        self.sessions = sessions
        self.projects = projects
        self.tags = tags
        self.ruleMatches = ruleMatches
        self.contextEvents = contextEvents
        self.migratedRawEvents = rawEvents
        self.migratedSessions = sessions
        self.migratedRuleMatches = ruleMatches
        self.migratedContextEvents = contextEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        assignments = try container.decodeIfPresent([String: UUID].self, forKey: .assignments) ?? [:]
        exclusions = try container.decodeIfPresent([ExclusionRule].self, forKey: .exclusions) ?? []
        focusSessions = try container.decodeIfPresent([FocusSession].self, forKey: .focusSessions) ?? []
        goals = try container.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        preferences = try container.decodeIfPresent(UserPreferences.self, forKey: .preferences) ?? .default
        
        // Event-heavy payloads are decoded for migration but not re-encoded to JSON.
        let decodedRaw = try container.decodeIfPresent([RawEvent].self, forKey: .rawEvents) ?? []
        let decodedSessions = try container.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        let decodedRuleMatches = try container.decodeIfPresent([RuleMatch].self, forKey: .ruleMatches) ?? []
        let decodedContextEvents = try container.decodeIfPresent([ContextEvent].self, forKey: .contextEvents) ?? []

        rawEvents = []
        sessions = []
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        ruleMatches = []
        contextEvents = []

        migratedRawEvents = decodedRaw
        migratedSessions = decodedSessions
        migratedRuleMatches = decodedRuleMatches
        migratedContextEvents = decodedContextEvents
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(categories, forKey: .categories)
        try container.encode(rules, forKey: .rules)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(exclusions, forKey: .exclusions)
        try container.encode(focusSessions, forKey: .focusSessions)
        try container.encode(goals, forKey: .goals)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(projects, forKey: .projects)
        try container.encode(tags, forKey: .tags)
    }
}

enum ActivityEventKey {
    static func make(appName: String, startTime: Date, endTime: Date) -> String {
        let start = Int(startTime.timeIntervalSince1970)
        let end = Int(endTime.timeIntervalSince1970)
        return "event|\(start)|\(end)|\(appName)"
    }
}

enum ActivityGrouping {
    static let separators: [String] = [" — ", " - ", ": "]

    static func split(appName: String) -> (app: String, title: String?) {
        for separator in separators {
            if let range = appName.range(of: separator) {
                let app = String(appName[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(appName[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !app.isEmpty, !title.isEmpty {
                    return (app, title)
                }
            }
        }
        return (appName, nil)
    }
}

extension ActivityEvent {
    var appDisplayName: String {
        ActivityGrouping.split(appName: appName).app
    }

    var windowTitle: String? {
        ActivityGrouping.split(appName: appName).title
    }
}

extension Color {
    init?(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6 else { return nil }
        let scanner = Scanner(string: sanitized)
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }

    func toHex() -> String {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
