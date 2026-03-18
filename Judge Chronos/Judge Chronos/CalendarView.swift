import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var selectedDate = Date()
    @State private var viewMode: CalendarViewMode = .month

    enum CalendarViewMode: String, CaseIterable {
        case month = "Month"
        case week = "Week"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .font(.title2)
                Text("Calendar")
                    .font(.title2)
                Spacer()

                Button(action: { navigateDate(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(headerTitle)
                    .font(.headline)
                    .frame(minWidth: 150)

                Button(action: { navigateDate(by: 1) }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Button("Today") { selectedDate = Date() }
                    .controlSize(.small)

                Picker("View", selection: $viewMode) {
                    ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding()

            Divider()

            switch viewMode {
            case .month:
                MonthGridView(selectedDate: $selectedDate, dataStore: dataStore)
            case .week:
                WeekGridView(selectedDate: $selectedDate, dataStore: dataStore)
            }
        }
    }

    private var headerTitle: String {
        let formatter = DateFormatter()
        switch viewMode {
        case .month:
            formatter.dateFormat = "MMMM yyyy"
        case .week:
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: selectedDate)
    }

    private func navigateDate(by value: Int) {
        let component: Calendar.Component = viewMode == .month ? .month : .weekOfYear
        if let newDate = Calendar.current.date(byAdding: component, value: value, to: selectedDate) {
            selectedDate = newDate
        }
    }
}

// MARK: - Month Grid
struct MonthGridView: View {
    @Binding var selectedDate: Date
    @ObservedObject var dataStore: LocalDataStore

    private let calendar = Calendar.current
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return [] }
        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1

        var days: [Date?] = Array(repeating: nil, count: firstWeekday)

        var current = firstDay
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }

        return days
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day headers
            HStack(spacing: 0) {
                ForEach(dayNames, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)

            // Calendar grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        MonthDayCell(date: date, isSelected: calendar.isDate(date, inSameDayAs: selectedDate), dataStore: dataStore)
                            .onTapGesture { selectedDate = date }
                    } else {
                        Color.clear
                            .frame(height: 80)
                    }
                }
            }

            Divider()

            // Day detail
            DayDetailView(date: selectedDate, dataStore: dataStore)
        }
    }
}

// MARK: - Month Day Cell
struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    @ObservedObject var dataStore: LocalDataStore

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var daySessions: [Session] {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return dataStore.sessions.filter { $0.startTime >= start && $0.startTime < end && !$0.isIdle }
    }

    private var totalHours: Double {
        daySessions.reduce(0) { $0 + $1.duration } / 3600
    }

    private var projectColors: [Color] {
        let projectIds = Set(daySessions.compactMap(\.projectId))
        return projectIds.prefix(4).map { pid in
            if let project = dataStore.projects.first(where: { $0.id == pid }) {
                return Color(hex: project.colorHex) ?? .gray
            }
            return .gray
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(dayNumber)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .accentColor : .primary)

            if totalHours > 0 {
                Text(String(format: "%.1fh", totalHours))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                HStack(spacing: 2) {
                    ForEach(Array(projectColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                    }
                }
            }

            Spacer()
        }
        .padding(4)
        .frame(height: 80)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .border(isSelected ? Color.accentColor : Color.clear, width: 1)
    }
}

// MARK: - Week Grid
struct WeekGridView: View {
    @Binding var selectedDate: Date
    @ObservedObject var dataStore: LocalDataStore

    private let calendar = Calendar.current
    private let hours = Array(6..<22)

    private var weekDays: [Date] {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                // Hour labels
                VStack(spacing: 0) {
                    ForEach(hours, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 40, height: 40, alignment: .topTrailing)
                            .padding(.trailing, 4)
                    }
                }

                // Day columns
                ForEach(weekDays, id: \.self) { day in
                    WeekDayColumn(date: day, hours: hours, dataStore: dataStore)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Week Day Column
struct WeekDayColumn: View {
    let date: Date
    let hours: [Int]
    @ObservedObject var dataStore: LocalDataStore

    private let calendar = Calendar.current

    private var daySessions: [Session] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return dataStore.sessions.filter { $0.startTime >= start && $0.startTime < end && !$0.isIdle }
    }

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day header
            Text(dayName)
                .font(.caption)
                .fontWeight(calendar.isDateInToday(date) ? .bold : .regular)
                .foregroundColor(calendar.isDateInToday(date) ? .accentColor : .primary)
                .padding(.bottom, 4)

            // Hour slots
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(hours, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 40)
                            .border(Color.gray.opacity(0.2), width: 0.5)
                    }
                }

                // Session blocks
                ForEach(daySessions) { session in
                    SessionBlock(session: session, dayStart: calendar.startOfDay(for: date), firstHour: hours.first ?? 6, dataStore: dataStore)
                }
            }
        }
    }
}

// MARK: - Session Block
struct SessionBlock: View {
    let session: Session
    let dayStart: Date
    let firstHour: Int
    @ObservedObject var dataStore: LocalDataStore

    private var yOffset: CGFloat {
        let sessionStart = session.startTime.timeIntervalSince(dayStart)
        let hourOffset = sessionStart / 3600 - Double(firstHour)
        return CGFloat(hourOffset) * 40
    }

    private var height: CGFloat {
        max(4, CGFloat(session.duration / 3600) * 40)
    }

    private var color: Color {
        if let projectId = session.projectId,
           let project = dataStore.projects.first(where: { $0.id == projectId }) {
            return Color(hex: project.colorHex) ?? .accentColor
        }
        return .accentColor
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(0.7))
            .frame(height: height)
            .overlay(
                Text(session.sourceApp)
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 2),
                alignment: .topLeading
            )
            .offset(y: yOffset)
            .padding(.horizontal, 1)
    }
}

// MARK: - Day Detail
struct DayDetailView: View {
    let date: Date
    @ObservedObject var dataStore: LocalDataStore

    private var daySessions: [Session] {
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return dataStore.sessions
            .filter { $0.startTime >= start && $0.startTime < end && !$0.isIdle }
            .sorted { $0.startTime < $1.startTime }
    }

    private var totalHours: Double {
        daySessions.reduce(0) { $0 + $1.duration } / 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let formatter = DateFormatter()
                Text({
                    let f = DateFormatter()
                    f.dateStyle = .full
                    return f.string(from: date)
                }())
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1f hours", totalHours))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if daySessions.isEmpty {
                Text("No activity recorded for this day")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(daySessions.prefix(20)) { session in
                            VStack(spacing: 2) {
                                Text(session.sourceApp)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                Text(Formatting.formatDuration(session.duration))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .padding(4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(height: 80)
    }
}
