import SwiftUI
import Charts

struct ProductivityDashboard: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @StateObject private var engine = ProductivityEngine.shared
    
    @State private var selectedPeriod: PeriodOption = .week
    @State private var selectedDate = Date()
    @State private var showingInsights = true
    
    enum PeriodOption: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                Text("Productivity")
                    .font(.title2)
                
                Spacer()
                
                // Period Selector
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(PeriodOption.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    // Score Cards
                    ScoreCardsSection(engine: engine, dataStore: dataStore)
                    
                    // Trend Chart
                    TrendChartSection(
                        selectedPeriod: selectedPeriod,
                        engine: engine,
                        dataStore: dataStore
                    )
                    
                    // Heatmap
                    ProductivityHeatmap(
                        selectedDate: $selectedDate,
                        engine: engine,
                        dataStore: dataStore
                    )
                    
                    // Insights
                    if showingInsights {
                        InsightsSection(engine: engine, dataStore: dataStore)
                    }
                    
                    // Peak Hours
                    PeakHoursSection(engine: engine, dataStore: dataStore)
                    
                    // Working Time / Overtime
                    OvertimeSection(dataStore: dataStore)

                    // Streaks
                    StreaksSection(engine: engine)
                }
                .padding()
            }
        }
        .padding()
        .onAppear {
            engine.calculateStreaks(dataStore: dataStore)
        }
    }
}

// MARK: - Score Cards Section
struct ScoreCardsSection: View {
    @ObservedObject var engine: ProductivityEngine
    @ObservedObject var dataStore: LocalDataStore
    
    private var todayScore: ProductivityScore {
        engine.calculateDailyScore(for: Date(), dataStore: dataStore)
    }
    
    private var scoreColor: Color {
        if todayScore.overallScore > 0.5 {
            return .green
        } else if todayScore.overallScore > 0 {
            return .yellow
        } else if todayScore.overallScore > -0.5 {
            return .orange
        }
        return .red
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Overall Score
            ScoreCard(
                title: "Today's Score",
                value: String(format: "%.1f", todayScore.overallScore),
                subtitle: scoreDescription(todayScore.overallScore),
                color: scoreColor,
                icon: "star.fill"
            )
            
            // Productive Hours
            ScoreCard(
                title: "Productive",
                value: String(format: "%.1f", todayScore.productiveHours),
                subtitle: "hours",
                color: .green,
                icon: "checkmark.circle.fill"
            )
            
            // Distracting Time
            ScoreCard(
                title: "Distracting",
                value: String(format: "%.1f", todayScore.distractingHours),
                subtitle: "hours",
                color: .orange,
                icon: "exclamationmark.circle.fill"
            )
            
            // Current Streak
            ScoreCard(
                title: "Streak",
                value: "\(engine.currentStreak)",
                subtitle: "days",
                color: .blue,
                icon: "flame.fill"
            )
        }
    }
    
    private func scoreDescription(_ score: Double) -> String {
        switch score {
        case 1.5...: return "Excellent"
        case 0.5..<1.5: return "Good"
        case -0.5..<0.5: return "Neutral"
        case -1.5..<(-0.5): return "Needs Work"
        default: return "Very Low"
        }
    }
}

struct ScoreCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Trend Chart Section
struct TrendChartSection: View {
    let selectedPeriod: ProductivityDashboard.PeriodOption
    @ObservedObject var engine: ProductivityEngine
    @ObservedObject var dataStore: LocalDataStore
    
    private var chartData: [(date: Date, score: Double)] {
        let calendar = Calendar.current
        var data: [(Date, Double)] = []
        
        let days: Int
        switch selectedPeriod {
        case .day: days = 1
        case .week: days = 7
        case .month: days = 30
        }
        
        for day in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -day, to: Date()) else { continue }
            let score = engine.calculateDailyScore(for: date, dataStore: dataStore)
            data.insert((date, score.overallScore), at: 0)
        }
        
        return data
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Productivity Trend")
                .font(.headline)
            
            Chart(chartData, id: \.date) { item in
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Score", item.score)
                )
                .foregroundStyle(scoreColor(item.score))
                .lineStyle(StrokeStyle(lineWidth: 2))
                
                AreaMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Score", item.score)
                )
                .foregroundStyle(scoreColor(item.score).opacity(0.1))
                
                PointMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Score", item.score)
                )
                .foregroundStyle(scoreColor(item.score))
            }
            .chartYScale(domain: -2...2)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 150)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score > 0.5 { return .green }
        if score > 0 { return .yellow }
        if score > -0.5 { return .orange }
        return .red
    }
}

// MARK: - Insights Section
struct InsightsSection: View {
    @ObservedObject var engine: ProductivityEngine
    @ObservedObject var dataStore: LocalDataStore
    
    private var todayInsights: [ProductivityInsight] {
        let score = engine.calculateDailyScore(for: Date(), dataStore: dataStore)
        return score.insights
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insights")
                    .font(.headline)
                Spacer()
                Text("\(todayInsights.count) today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if todayInsights.isEmpty {
                Text("No insights for today yet. Keep tracking to see personalized recommendations.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(todayInsights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct InsightCard: View {
    let insight: ProductivityInsight
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.type.icon)
                .font(.title3)
                .foregroundColor(insight.type.color)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(insight.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let action = insight.suggestedAction {
                    Text(action)
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Peak Hours Section
struct PeakHoursSection: View {
    @ObservedObject var engine: ProductivityEngine
    @ObservedObject var dataStore: LocalDataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Peak Hours")
                .font(.headline)
            
            // Simple bar chart for peak hours
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(8..<20, id: \.self) { hour in
                    PeakHourBar(hour: hour, engine: engine, dataStore: dataStore)
                }
            }
            .frame(height: 80)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct PeakHourBar: View {
    let hour: Int
    @ObservedObject var engine: ProductivityEngine
    @ObservedObject var dataStore: LocalDataStore
    
    private var productivity: Double {
        // Calculate average productivity for this hour over last 7 days
        var totalScore: Double = 0
        var count = 0
        
        for day in 0..<7 {
            guard let date = Calendar.current.date(byAdding: .day, value: -day, to: Date()) else { continue }
            let score = engine.calculateDailyScore(for: date, dataStore: dataStore)
            totalScore += score.overallScore
            count += 1
        }
        
        return count > 0 ? totalScore / Double(count) : 0
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(productivity > 0 ? Color.green : Color.gray)
                .frame(width: 20, height: max(10, abs(productivity) * 30))
                .cornerRadius(4)
            
            Text("\(hour)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Streaks Section
struct StreaksSection: View {
    @ObservedObject var engine: ProductivityEngine
    
    var body: some View {
        HStack(spacing: 16) {
            StreakCard(
                title: "Current Streak",
                value: engine.currentStreak,
                subtitle: "consecutive productive days",
                color: .orange
            )
            
            StreakCard(
                title: "Best Streak",
                value: engine.bestStreak,
                subtitle: "your personal record",
                color: .green
            )
        }
    }
}

struct StreakCard: View {
    let title: String
    let value: Int
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 36, weight: .bold))
                Text("days")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Overtime Section
struct OvertimeSection: View {
    @ObservedObject var dataStore: LocalDataStore

    private var weeklySummary: [WorkScheduleService.DailySummary] {
        WorkScheduleService.shared.weeklySummary(for: Date(), dataStore: dataStore)
    }

    private var weeklyOvertimeTotal: TimeInterval {
        WorkScheduleService.shared.weeklyOvertime(for: Date(), dataStore: dataStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Working Time")
                    .font(.headline)
                Spacer()
                let otHours = weeklyOvertimeTotal / 3600
                Text(String(format: "%+.1fh overtime", otHours))
                    .font(.caption)
                    .foregroundColor(otHours > 0 ? .orange : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((otHours > 0 ? Color.orange : Color.green).opacity(0.1))
                    .cornerRadius(6)
            }

            // Daily breakdown
            HStack(spacing: 8) {
                ForEach(weeklySummary, id: \.date) { day in
                    VStack(spacing: 4) {
                        let formatter = DateFormatter()
                        Text({
                            let f = DateFormatter()
                            f.dateFormat = "EEE"
                            return f.string(from: day.date)
                        }())
                            .font(.caption2)
                            .foregroundColor(day.isWorkDay ? .primary : .secondary)

                        ZStack(alignment: .bottom) {
                            // Expected (background)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 24, height: CGFloat(day.expectedHours) * 8)

                            // Actual
                            RoundedRectangle(cornerRadius: 3)
                                .fill(day.overtimeHours > 0 ? Color.orange : Color.green)
                                .frame(width: 24, height: CGFloat(min(day.actualHours, 12)) * 8)
                        }
                        .frame(height: 64)

                        Text(String(format: "%.1f", day.actualHours))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        if day.breakHours > 0 {
                            Text(String(format: "%.0fm brk", day.breakHours * 60))
                                .font(.system(size: 8))
                                .foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Preview
#Preview {
    ProductivityDashboard()
        .environmentObject(LocalDataStore.shared)
        .frame(width: 800, height: 900)
}
