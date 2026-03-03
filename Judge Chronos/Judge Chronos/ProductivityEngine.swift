import Foundation
import SwiftUI

// MARK: - Productivity Score Model
struct ProductivityScore: Identifiable, Codable {
    let id: UUID
    let date: Date
    var overallScore: Double // -2.0 to 2.0
    var productiveHours: TimeInterval
    var distractingHours: TimeInterval
    var neutralHours: TimeInterval
    var sessionBreakdown: [ProductivityCategory: TimeInterval]
    var insights: [ProductivityInsight]
    
    init(
        id: UUID = UUID(),
        date: Date,
        overallScore: Double = 0,
        productiveHours: TimeInterval = 0,
        distractingHours: TimeInterval = 0,
        neutralHours: TimeInterval = 0,
        sessionBreakdown: [ProductivityCategory: TimeInterval] = [:],
        insights: [ProductivityInsight] = []
    ) {
        self.id = id
        self.date = date
        self.overallScore = overallScore
        self.productiveHours = productiveHours
        self.distractingHours = distractingHours
        self.neutralHours = neutralHours
        self.sessionBreakdown = sessionBreakdown
        self.insights = insights
    }
}

enum ProductivityCategory: String, Codable, CaseIterable {
    case veryProductive = "Very Productive"
    case productive = "Productive"
    case neutral = "Neutral"
    case distracting = "Distracting"
    case veryDistracting = "Very Distracting"
    
    var rating: ProductivityRating {
        switch self {
        case .veryProductive: return .veryProductive
        case .productive: return .productive
        case .neutral: return .neutral
        case .distracting: return .distracting
        case .veryDistracting: return .veryDistracting
        }
    }
    
    var color: Color {
        rating.color
    }
    
    var scoreValue: Double {
        Double(rating.rawValue)
    }
}

// MARK: - Productivity Insight
struct ProductivityInsight: Identifiable, Codable {
    let id: UUID
    let type: InsightType
    let title: String
    let description: String
    let actionable: Bool
    let suggestedAction: String?
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        type: InsightType,
        title: String,
        description: String,
        actionable: Bool = false,
        suggestedAction: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.actionable = actionable
        self.suggestedAction = suggestedAction
        self.createdAt = createdAt
    }
}

enum InsightType: String, Codable {
    case peakHours = "peak_hours"
    case distractingApps = "distracting_apps"
    case streak = "streak"
    case improvement = "improvement"
    case decline = "decline"
    case focusTime = "focus_time"
    case workLifeBalance = "work_life_balance"
    case mostProductiveDay = "most_productive_day"
    case leastProductiveDay = "least_productive_day"
    
    var icon: String {
        switch self {
        case .peakHours: return "sun.max.fill"
        case .distractingApps: return "exclamationmark.triangle"
        case .streak: return "flame.fill"
        case .improvement: return "arrow.up.forward"
        case .decline: return "arrow.down.forward"
        case .focusTime: return "target"
        case .workLifeBalance: return "figure.walk"
        case .mostProductiveDay: return "star.fill"
        case .leastProductiveDay: return "cloud.rain"
        }
    }
    
    var color: Color {
        switch self {
        case .peakHours, .streak, .improvement, .mostProductiveDay, .focusTime:
            return .green
        case .distractingApps, .decline, .leastProductiveDay:
            return .orange
        case .workLifeBalance:
            return .blue
        }
    }
}

// MARK: - Trend Direction
enum TrendDirection: String, Codable {
    case up = "up"
    case down = "down"
    case stable = "stable"
    
    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .stable: return "minus"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .stable: return .gray
        }
    }
}

// MARK: - Productivity Trend
struct ProductivityTrend {
    let period: DateInterval
    let averageScore: Double
    let trendDirection: TrendDirection
    let comparedToPrevious: Double // percentage change
    let totalProductiveHours: TimeInterval
    let totalDistractingHours: TimeInterval
}

// MARK: - Hourly Productivity
struct HourlyProductivity {
    let hour: Int // 0-23
    let averageScore: Double
    let totalTime: TimeInterval
    let isPeakTime: Bool
}

// MARK: - Productivity Engine
@MainActor
final class ProductivityEngine: ObservableObject {
    static let shared = ProductivityEngine()
    
    @Published private(set) var dailyScores: [Date: ProductivityScore] = [:]
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    
    // Known productive/distracting domains
    private let productiveDomains: Set<String> = [
        "github.com", "gitlab.com", "bitbucket.org",
        "stackoverflow.com", "docs.microsoft.com", "developer.apple.com",
        "figma.com", "sketch.com", "linear.app", "jira.com", "asana.com",
        "notion.so", "confluence.atlassian.com",
        "slack.com", "zoom.us"
    ]
    
    private let distractingDomains: Set<String> = [
        "facebook.com", "twitter.com", "x.com", "instagram.com",
        "tiktok.com", "youtube.com", "reddit.com", "netflix.com",
        "twitch.tv"
    ]
    
    private init() {}
    
    // MARK: - Calculate Daily Score
    func calculateDailyScore(for date: Date, dataStore: LocalDataStore) -> ProductivityScore {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        
        // Get sessions for this day
        let sessions = dataStore.sessions.filter {
            $0.startTime >= startOfDay && $0.startTime < endOfDay
        }
        
        var breakdown: [ProductivityCategory: TimeInterval] = [:]
        var productiveTime: TimeInterval = 0
        var distractingTime: TimeInterval = 0
        var neutralTime: TimeInterval = 0
        
        for session in sessions {
            let category = categorizeSession(session, dataStore: dataStore)
            breakdown[category, default: 0] += session.duration
            
            switch category {
            case .veryProductive, .productive:
                productiveTime += session.duration
            case .distracting, .veryDistracting:
                distractingTime += session.duration
            case .neutral:
                neutralTime += session.duration
            }
        }
        
        let totalTime = productiveTime + distractingTime + neutralTime
        let overallScore = totalTime > 0 ? 
            (productiveTime - distractingTime) / totalTime * 2 : 0
        
        let insights = generateInsights(
            for: date,
            sessions: sessions,
            breakdown: breakdown,
            dataStore: dataStore
        )
        
        return ProductivityScore(
            date: date,
            overallScore: max(-2, min(2, overallScore)),
            productiveHours: productiveTime / 3600,
            distractingHours: distractingTime / 3600,
            neutralHours: neutralTime / 3600,
            sessionBreakdown: breakdown,
            insights: insights
        )
    }
    
    // MARK: - Categorize Session
    private func categorizeSession(_ session: Session, dataStore: LocalDataStore) -> ProductivityCategory {
        // Check project rating first
        if let projectId = session.projectId,
           let project = dataStore.projects.first(where: { $0.id == projectId }),
           let rating = project.productivityRating {
            return category(from: rating)
        }
        
        // Check domain/productivity from window title
        let appName = session.sourceApp.lowercased()
        let windowTitle = session.lastWindowTitle?.lowercased() ?? ""
        
        // Check for distracting domains
        for domain in distractingDomains {
            if appName.contains(domain) || windowTitle.contains(domain) {
                return .distracting
            }
        }
        
        // Check for productive domains
        for domain in productiveDomains {
            if appName.contains(domain) || windowTitle.contains(domain) {
                return .productive
            }
        }
        
        // Default categorization based on app type
        if appName.contains("safari") || appName.contains("chrome") {
            return .neutral
        }
        
        // Productivity apps
        let productiveApps = ["xcode", "vscode", "terminal", "cursor"]
        if productiveApps.contains(where: { appName.contains($0) }) {
            return .productive
        }
        
        return .neutral
    }
    
    private func category(from rating: ProductivityRating) -> ProductivityCategory {
        switch rating {
        case .veryProductive: return .veryProductive
        case .productive: return .productive
        case .neutral: return .neutral
        case .distracting: return .distracting
        case .veryDistracting: return .veryDistracting
        }
    }
    
    // MARK: - Generate Insights
    private func generateInsights(
        for date: Date,
        sessions: [Session],
        breakdown: [ProductivityCategory: TimeInterval],
        dataStore: LocalDataStore
    ) -> [ProductivityInsight] {
        var insights: [ProductivityInsight] = []
        
        // Peak hours insight
        let hourlyData = calculateHourlyProductivity(for: date, sessions: sessions)
        if let peakHour = hourlyData.filter({ $0.isPeakTime }).max(by: { $0.averageScore < $1.averageScore }) {
            insights.append(ProductivityInsight(
                type: .peakHours,
                title: "Peak Productivity",
                description: "You're most productive around \(formatHour(peakHour.hour))",
                actionable: true,
                suggestedAction: "Schedule important work during this time"
            ))
        }
        
        // Distracting apps insight
        let distractingTime = breakdown[.distracting] ?? 0 + (breakdown[.veryDistracting] ?? 0)
        if distractingTime > 3600 { // More than 1 hour
            let distractingApps = sessions
                .filter { categorizeSession($0, dataStore: dataStore) == .distracting }
                .map { $0.sourceApp }
            
            if let mostDistracting = distractingApps.mostCommon() {
                insights.append(ProductivityInsight(
                    type: .distractingApps,
                    title: "Time in \(mostDistracting)",
                    description: "You spent \(formatDuration(distractingTime)) in distracting apps today",
                    actionable: true,
                    suggestedAction: "Consider using Focus mode during work hours"
                ))
            }
        }
        
        // Focus time insight
        let productiveTime = breakdown[.productive] ?? 0 + (breakdown[.veryProductive] ?? 0)
        if productiveTime > 14400 { // More than 4 hours
            insights.append(ProductivityInsight(
                type: .focusTime,
                title: "Great Focus Day!",
                description: "You had \(formatDuration(productiveTime)) of productive time",
                actionable: false
            ))
        }
        
        return insights
    }
    
    // MARK: - Calculate Hourly Productivity
    private func calculateHourlyProductivity(for date: Date, sessions: [Session]) -> [HourlyProductivity] {
        var hourlyData: [Int: (totalScore: Double, totalTime: TimeInterval)] = [:]
        
        for session in sessions {
            let hour = Calendar.current.component(.hour, from: session.startTime)
            let category = categorizeSession(session, dataStore: LocalDataStore.shared)
            let score = category.scoreValue
            
            let current = hourlyData[hour] ?? (0, 0)
            hourlyData[hour] = (
                totalScore: current.totalScore + score * session.duration,
                totalTime: current.totalTime + session.duration
            )
        }
        
        return (0..<24).map { hour in
            let data = hourlyData[hour] ?? (0, 0)
            let avgScore = data.totalTime > 0 ? data.totalScore / data.totalTime : 0
            return HourlyProductivity(
                hour: hour,
                averageScore: avgScore,
                totalTime: data.totalTime,
                isPeakTime: avgScore > 0.5 && data.totalTime > 1800
            )
        }
    }
    
    // MARK: - Calculate Trend
    func calculateTrend(
        for period: DateInterval,
        dataStore: LocalDataStore
    ) -> ProductivityTrend {
        let calendar = Calendar.current
        
        // Calculate current period
        var currentScores: [Double] = []
        var currentProductive: TimeInterval = 0
        var currentDistracting: TimeInterval = 0
        
        var date = period.start
        while date < period.end {
            let score = calculateDailyScore(for: date, dataStore: dataStore)
            currentScores.append(score.overallScore)
            currentProductive += score.productiveHours
            currentDistracting += score.distractingHours
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        
        let currentAverage = currentScores.isEmpty ? 0 : currentScores.reduce(0, +) / Double(currentScores.count)
        
        // Calculate previous period for comparison
        let previousPeriod = DateInterval(
            start: calendar.date(byAdding: .day, value: -Int(period.duration / 86400), to: period.start) ?? period.start,
            end: period.start
        )
        
        var previousScores: [Double] = []
        date = previousPeriod.start
        while date < previousPeriod.end {
            let score = calculateDailyScore(for: date, dataStore: dataStore)
            previousScores.append(score.overallScore)
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        
        let previousAverage = previousScores.isEmpty ? 0 : previousScores.reduce(0, +) / Double(previousScores.count)
        
        let percentageChange = previousAverage != 0 ? 
            ((currentAverage - previousAverage) / abs(previousAverage)) * 100 : 0
        
        let direction: TrendDirection
        if percentageChange > 5 {
            direction = .up
        } else if percentageChange < -5 {
            direction = .down
        } else {
            direction = .stable
        }
        
        return ProductivityTrend(
            period: period,
            averageScore: currentAverage,
            trendDirection: direction,
            comparedToPrevious: percentageChange,
            totalProductiveHours: currentProductive,
            totalDistractingHours: currentDistracting
        )
    }
    
    // MARK: - Streaks
    func calculateStreaks(dataStore: LocalDataStore) {
        var currentCount = 0
        var bestCount = 0
        var date = Calendar.current.startOfDay(for: Date())
        
        // Calculate current streak (going backwards from today)
        while true {
            let score = calculateDailyScore(for: date, dataStore: dataStore)
            if score.overallScore > 0 {
                currentCount += 1
                date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
            } else {
                break
            }
        }
        
        // Calculate best streak (scan last 90 days)
        var tempStreak = 0
        date = Calendar.current.startOfDay(for: Date())
        
        for _ in 0..<90 {
            let score = calculateDailyScore(for: date, dataStore: dataStore)
            if score.overallScore > 0 {
                tempStreak += 1
                bestCount = max(bestCount, tempStreak)
            } else {
                tempStreak = 0
            }
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        
        currentStreak = currentCount
        bestStreak = bestCount
    }
    
    // MARK: - Suggestions
    func suggestImprovements(dataStore: LocalDataStore) -> [String] {
        var suggestions: [String] = []
        
        // Analyze patterns
        let last30Days = (0..<30).compactMap { day -> ProductivityScore? in
            guard let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) else { return nil }
            return calculateDailyScore(for: date, dataStore: dataStore)
        }
        
        // Check for consistent low productivity
        let lowProductivityDays = last30Days.filter { $0.overallScore < 0 }.count
        if lowProductivityDays > 10 {
            suggestions.append("Consider reviewing your project categories - you've had \(lowProductivityDays) low productivity days this month")
        }
        
        // Check for peak hours
        let allHours = last30Days.flatMap { score in
            (0..<24).map { hour -> (hour: Int, score: Double) in
                (hour, score.overallScore)
            }
        }
        
        let hourlyAverages = Dictionary(grouping: allHours) { $0.hour }
            .mapValues { $0.map { $0.score }.reduce(0, +) / Double($0.count) }
        
        if let bestHour = hourlyAverages.max(by: { $0.value < $1.value }) {
            suggestions.append("Your peak productivity is at \(formatHour(bestHour.key)) - schedule important tasks then")
        }
        
        return suggestions
    }
    
    // MARK: - Helper Functions
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Array Extensions
extension Array where Element: Hashable {
    func mostCommon() -> Element? {
        let counts = reduce(into: [:]) { counts, element in
            counts[element, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }
}
