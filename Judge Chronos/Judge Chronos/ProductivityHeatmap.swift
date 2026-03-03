import SwiftUI

struct ProductivityHeatmap: View {
    @Binding var selectedDate: Date
    @ObservedObject var engine: ProductivityEngine
    @ObservedObject var dataStore: LocalDataStore
    
    @State private var selectedMonth = Date()
    
    private let calendar = Calendar.current
    private let daysInWeek = 7
    private let weeksToShow = 12 // Show 12 weeks
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Activity Heatmap")
                    .font(.headline)
                
                Spacer()
                
                // Month navigation
                HStack(spacing: 8) {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    
                    Text(monthYearString(selectedMonth))
                        .font(.subheadline)
                        .frame(width: 120)
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Legend
            HStack(spacing: 4) {
                Text("Low")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                ForEach(0..<5) { level in
                    Rectangle()
                        .fill(colorForLevel(level))
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                }
                
                Text("High")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Heatmap Grid
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // Day labels
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                            Text(day)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(height: 20)
                        }
                    }
                    
                    // Weeks
                    ForEach(monthWeeks, id: \.self) { week in
                        VStack(spacing: 4) {
                            ForEach(week, id: \.self) { date in
                                DayCell(
                                    date: date,
                                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                    productivityColor: productivityColor(for: date)
                                )
                                .onTapGesture {
                                    selectedDate = date
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Selected day details
            SelectedDayDetails(
                date: selectedDate,
                engine: engine,
                dataStore: dataStore
            )
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    private var monthWeeks: [[Date]] {
        var weeks: [[Date]] = []
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let range = calendar.range(of: .weekOfMonth, in: .month, for: startOfMonth)!
        
        for week in range {
            var weekDates: [Date] = []
            for day in 1...7 {
                if let date = calendar.date(byAdding: .day, value: (week - 1) * 7 + day - 1 - calendar.component(.weekday, from: startOfMonth) + 2, to: startOfMonth) {
                    weekDates.append(date)
                }
            }
            if !weekDates.isEmpty {
                weeks.append(weekDates)
            }
        }
        
        return weeks
    }
    
    // MARK: - Helper Methods
    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    private func productivityColor(for date: Date) -> Color {
        let score = engine.calculateDailyScore(for: date, dataStore: dataStore)
        return colorForScore(score.overallScore)
    }
    
    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 1.5...:
            return Color.green.opacity(0.9)
        case 0.5..<1.5:
            return Color.green.opacity(0.6)
        case -0.5..<0.5:
            return Color.green.opacity(0.3)
        case -1.5..<(-0.5):
            return Color.orange.opacity(0.5)
        default:
            return Color.red.opacity(0.5)
        }
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 0: return Color.gray.opacity(0.2)
        case 1: return Color.green.opacity(0.3)
        case 2: return Color.green.opacity(0.5)
        case 3: return Color.green.opacity(0.7)
        default: return Color.green.opacity(0.9)
        }
    }
}

// MARK: - Day Cell
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let productivityColor: Color
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var isFuture: Bool {
        date > Date()
    }
    
    var body: some View {
        Rectangle()
            .fill(isFuture ? Color.gray.opacity(0.1) : productivityColor)
            .frame(width: 20, height: 20)
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.accentColor : (isToday ? Color.blue : Color.clear), lineWidth: isSelected ? 2 : 1)
            )
    }
}

// MARK: - Selected Day Details
struct SelectedDayDetails: View {
    let date: Date
    @ObservedObject var engine: ProductivityEngine
    @ObservedObject var dataStore: LocalDataStore
    
    private var score: ProductivityScore {
        engine.calculateDailyScore(for: date, dataStore: dataStore)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isToday ? "Today" : formattedDate(date))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Score badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(scoreColor(score.overallScore))
                        .frame(width: 8, height: 8)
                    Text("Score: \(String(format: "%.1f", score.overallScore))")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(scoreColor(score.overallScore).opacity(0.1))
                .cornerRadius(12)
            }
            
            // Time breakdown
            HStack(spacing: 16) {
                TimeBreakdownItem(
                    label: "Productive",
                    hours: score.productiveHours,
                    color: .green
                )
                
                TimeBreakdownItem(
                    label: "Neutral",
                    hours: score.neutralHours,
                    color: .gray
                )
                
                TimeBreakdownItem(
                    label: "Distracting",
                    hours: score.distractingHours,
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score > 0.5 { return .green }
        if score > 0 { return .yellow }
        if score > -0.5 { return .orange }
        return .red
    }
}

struct TimeBreakdownItem: View {
    let label: String
    let hours: TimeInterval
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1fh", hours))
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ProductivityHeatmap(
        selectedDate: .constant(Date()),
        engine: ProductivityEngine.shared,
        dataStore: LocalDataStore.shared
    )
    .frame(width: 600, height: 400)
    .padding()
}
