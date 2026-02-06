import AppKit
import Foundation
import SwiftUI

enum ActivityEventSource: String, Hashable {
    case appUsage
    case calendar
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
    var rawEventIds: [UUID]
    var projectId: UUID?
    var categoryId: UUID?
    var tagIds: Set<UUID>
    var note: String?
    var isPrivate: Bool
    var isIdle: Bool
}

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var parentId: UUID?
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
    var categoryId: UUID { targetCategoryId ?? UUID() }
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
        calendarIntegrationEnabled: false,
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
        
        // Phase 0: Decode new models
        rawEvents = try container.decodeIfPresent([RawEvent].self, forKey: .rawEvents) ?? []
        sessions = try container.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        ruleMatches = try container.decodeIfPresent([RuleMatch].self, forKey: .ruleMatches) ?? []
        contextEvents = try container.decodeIfPresent([ContextEvent].self, forKey: .contextEvents) ?? []
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
