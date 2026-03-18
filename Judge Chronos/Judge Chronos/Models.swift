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
    var activityId: UUID?
    var isBreak: Bool

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
        isIdle: Bool,
        activityId: UUID? = nil,
        isBreak: Bool = false
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
        self.activityId = activityId
        self.isBreak = isBreak
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
        case activityId
        case isBreak
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
        activityId = try container.decodeIfPresent(UUID.self, forKey: .activityId)
        isBreak = try container.decodeIfPresent(Bool.self, forKey: .isBreak) ?? false
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
    var clientId: UUID?
    var productivityRating: ProductivityRating?
    var hourlyRate: Double?
    var isBillable: Bool
    var archived: Bool
    var createdAt: Date
    var timeBudgetSeconds: TimeInterval?
    var moneyBudget: Double?

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        parentId: UUID? = nil,
        clientId: UUID? = nil,
        productivityRating: ProductivityRating? = nil,
        hourlyRate: Double? = nil,
        isBillable: Bool = false,
        archived: Bool = false,
        createdAt: Date = Date(),
        timeBudgetSeconds: TimeInterval? = nil,
        moneyBudget: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.parentId = parentId
        self.clientId = clientId
        self.productivityRating = productivityRating
        self.hourlyRate = hourlyRate
        self.isBillable = isBillable
        self.archived = archived
        self.createdAt = createdAt
        self.timeBudgetSeconds = timeBudgetSeconds
        self.moneyBudget = moneyBudget
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
    var targetActivityId: UUID?
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

// MARK: - Client Entity
struct Client: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var company: String?
    var address: String?
    var email: String?
    var phone: String?
    var vatId: String?
    var currency: String
    var defaultHourlyRate: Double?
    var defaultInvoiceNotes: String?
    var archived: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        company: String? = nil,
        address: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        vatId: String? = nil,
        currency: String = "USD",
        defaultHourlyRate: Double? = nil,
        defaultInvoiceNotes: String? = nil,
        archived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.company = company
        self.address = address
        self.email = email
        self.phone = phone
        self.vatId = vatId
        self.currency = currency
        self.defaultHourlyRate = defaultHourlyRate
        self.defaultInvoiceNotes = defaultInvoiceNotes
        self.archived = archived
        self.createdAt = createdAt
    }
}

// MARK: - Activity Entity (tasks within projects)
struct Activity: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var projectId: UUID?
    var colorHex: String?
    var isBillable: Bool
    var hourlyRate: Double?
    var archived: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        projectId: UUID? = nil,
        colorHex: String? = nil,
        isBillable: Bool = true,
        hourlyRate: Double? = nil,
        archived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectId = projectId
        self.colorHex = colorHex
        self.isBillable = isBillable
        self.hourlyRate = hourlyRate
        self.archived = archived
        self.createdAt = createdAt
    }
}

// MARK: - Manual Timer
struct ManualTimer: Identifiable, Codable, Hashable {
    let id: UUID
    var projectId: UUID?
    var activityId: UUID?
    var description: String?
    var startedAt: Date
    var stoppedAt: Date?
    var tagIds: Set<UUID>
    var isBillable: Bool

    init(
        id: UUID = UUID(),
        projectId: UUID? = nil,
        activityId: UUID? = nil,
        description: String? = nil,
        startedAt: Date = Date(),
        stoppedAt: Date? = nil,
        tagIds: Set<UUID> = [],
        isBillable: Bool = true
    ) {
        self.id = id
        self.projectId = projectId
        self.activityId = activityId
        self.description = description
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.tagIds = tagIds
        self.isBillable = isBillable
    }

    var isRunning: Bool { stoppedAt == nil }

    var elapsed: TimeInterval {
        let end = stoppedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }
}

// MARK: - Invoice
enum InvoiceStatus: String, Codable, CaseIterable {
    case draft
    case sent
    case paid
    case overdue
}

struct Invoice: Identifiable, Codable, Hashable {
    let id: UUID
    var invoiceNumber: String
    var clientId: UUID?
    var status: InvoiceStatus
    var createdAt: Date
    var dueDate: Date?
    var paidAt: Date?
    var totalAmount: Double
    var taxAmount: Double
    var currency: String
    var notes: String?
    var sessionIds: [UUID]
    var pdfData: Data?

    init(
        id: UUID = UUID(),
        invoiceNumber: String,
        clientId: UUID? = nil,
        status: InvoiceStatus = .draft,
        createdAt: Date = Date(),
        dueDate: Date? = nil,
        paidAt: Date? = nil,
        totalAmount: Double = 0,
        taxAmount: Double = 0,
        currency: String = "USD",
        notes: String? = nil,
        sessionIds: [UUID] = [],
        pdfData: Data? = nil
    ) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.clientId = clientId
        self.status = status
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.paidAt = paidAt
        self.totalAmount = totalAmount
        self.taxAmount = taxAmount
        self.currency = currency
        self.notes = notes
        self.sessionIds = sessionIds
        self.pdfData = pdfData
    }
}

// MARK: - Favorite (Quick Entry)
struct Favorite: Identifiable, Codable, Hashable {
    let id: UUID
    var projectId: UUID?
    var activityId: UUID?
    var description: String?
    var isBillable: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        projectId: UUID? = nil,
        activityId: UUID? = nil,
        description: String? = nil,
        isBillable: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.projectId = projectId
        self.activityId = activityId
        self.description = description
        self.isBillable = isBillable
        self.sortOrder = sortOrder
    }
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

    // Kimai features
    var currency: String
    var invoiceNumberPrefix: String
    var nextInvoiceNumber: Int
    var defaultHourlyRate: Double?
    var workingDays: [Int]
    var expectedHoursPerDay: Double

    init(
        hasCompletedOnboarding: Bool = false,
        workDayStart: String = "09:00",
        workDayEnd: String = "17:00",
        privateModeEnabled: Bool = false,
        reviewReminderEnabled: Bool = false,
        reviewReminderTime: String = "17:30",
        weeklyRecapEnabled: Bool = true,
        goalNudgesEnabled: Bool = false,
        emailSummaryEnabled: Bool = false,
        calendarIntegrationEnabled: Bool = true,
        iCloudBackupEnabled: Bool = false,
        lastImportTimestamp: Date? = nil,
        lastImportHash: String? = nil,
        currency: String = "USD",
        invoiceNumberPrefix: String = "INV-",
        nextInvoiceNumber: Int = 1,
        defaultHourlyRate: Double? = nil,
        workingDays: [Int] = [1, 2, 3, 4, 5],
        expectedHoursPerDay: Double = 8.0
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.workDayStart = workDayStart
        self.workDayEnd = workDayEnd
        self.privateModeEnabled = privateModeEnabled
        self.reviewReminderEnabled = reviewReminderEnabled
        self.reviewReminderTime = reviewReminderTime
        self.weeklyRecapEnabled = weeklyRecapEnabled
        self.goalNudgesEnabled = goalNudgesEnabled
        self.emailSummaryEnabled = emailSummaryEnabled
        self.calendarIntegrationEnabled = calendarIntegrationEnabled
        self.iCloudBackupEnabled = iCloudBackupEnabled
        self.lastImportTimestamp = lastImportTimestamp
        self.lastImportHash = lastImportHash
        self.currency = currency
        self.invoiceNumberPrefix = invoiceNumberPrefix
        self.nextInvoiceNumber = nextInvoiceNumber
        self.defaultHourlyRate = defaultHourlyRate
        self.workingDays = workingDays
        self.expectedHoursPerDay = expectedHoursPerDay
    }

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
        lastImportHash: nil,
        currency: "USD",
        invoiceNumberPrefix: "INV-",
        nextInvoiceNumber: 1,
        defaultHourlyRate: nil,
        workingDays: [1, 2, 3, 4, 5],
        expectedHoursPerDay: 8.0
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        workDayStart = try container.decodeIfPresent(String.self, forKey: .workDayStart) ?? "09:00"
        workDayEnd = try container.decodeIfPresent(String.self, forKey: .workDayEnd) ?? "17:00"
        privateModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .privateModeEnabled) ?? false
        reviewReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reviewReminderEnabled) ?? false
        reviewReminderTime = try container.decodeIfPresent(String.self, forKey: .reviewReminderTime) ?? "17:30"
        weeklyRecapEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklyRecapEnabled) ?? true
        goalNudgesEnabled = try container.decodeIfPresent(Bool.self, forKey: .goalNudgesEnabled) ?? false
        emailSummaryEnabled = try container.decodeIfPresent(Bool.self, forKey: .emailSummaryEnabled) ?? false
        calendarIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarIntegrationEnabled) ?? true
        iCloudBackupEnabled = try container.decodeIfPresent(Bool.self, forKey: .iCloudBackupEnabled) ?? false
        lastImportTimestamp = try container.decodeIfPresent(Date.self, forKey: .lastImportTimestamp)
        lastImportHash = try container.decodeIfPresent(String.self, forKey: .lastImportHash)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        invoiceNumberPrefix = try container.decodeIfPresent(String.self, forKey: .invoiceNumberPrefix) ?? "INV-"
        nextInvoiceNumber = try container.decodeIfPresent(Int.self, forKey: .nextInvoiceNumber) ?? 1
        defaultHourlyRate = try container.decodeIfPresent(Double.self, forKey: .defaultHourlyRate)
        workingDays = try container.decodeIfPresent([Int].self, forKey: .workingDays) ?? [1, 2, 3, 4, 5]
        expectedHoursPerDay = try container.decodeIfPresent(Double.self, forKey: .expectedHoursPerDay) ?? 8.0
    }
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

    // Kimai feature entities
    var clients: [Client] = []
    var activities: [Activity] = []
    var manualTimers: [ManualTimer] = []
    var invoices: [Invoice] = []
    var favorites: [Favorite] = []

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
        case clients
        case activities
        case manualTimers
        case invoices
        case favorites
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
        contextEvents: [ContextEvent] = [],
        clients: [Client] = [],
        activities: [Activity] = [],
        manualTimers: [ManualTimer] = [],
        invoices: [Invoice] = [],
        favorites: [Favorite] = []
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
        self.clients = clients
        self.activities = activities
        self.manualTimers = manualTimers
        self.invoices = invoices
        self.favorites = favorites
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

        clients = try container.decodeIfPresent([Client].self, forKey: .clients) ?? []
        activities = try container.decodeIfPresent([Activity].self, forKey: .activities) ?? []
        manualTimers = try container.decodeIfPresent([ManualTimer].self, forKey: .manualTimers) ?? []
        invoices = try container.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
        favorites = try container.decodeIfPresent([Favorite].self, forKey: .favorites) ?? []

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
        try container.encode(clients, forKey: .clients)
        try container.encode(activities, forKey: .activities)
        try container.encode(manualTimers, forKey: .manualTimers)
        try container.encode(invoices, forKey: .invoices)
        try container.encode(favorites, forKey: .favorites)
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
