import Foundation

@MainActor
final class WorkScheduleService {
    static let shared = WorkScheduleService()

    private init() {}

    func isWorkDay(_ date: Date, preferences: UserPreferences) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return preferences.workingDays.contains(weekday)
    }

    func expectedHours(for date: Date, preferences: UserPreferences) -> Double {
        guard isWorkDay(date, preferences: preferences) else { return 0 }
        return preferences.expectedHoursPerDay
    }

    func actualHours(for date: Date, dataStore: LocalDataStore) -> TimeInterval {
        let startOfDay = Calendar.current.startOfDay(for: date)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }

        return dataStore.sessions
            .filter { $0.startTime >= startOfDay && $0.endTime <= endOfDay && !$0.isIdle && !$0.isBreak }
            .reduce(0) { $0 + $1.duration }
    }

    func breakTime(for date: Date, dataStore: LocalDataStore) -> TimeInterval {
        let startOfDay = Calendar.current.startOfDay(for: date)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }

        return dataStore.sessions
            .filter { $0.startTime >= startOfDay && $0.endTime <= endOfDay && $0.isBreak }
            .reduce(0) { $0 + $1.duration }
    }

    func overtime(for date: Date, dataStore: LocalDataStore) -> TimeInterval {
        let actual = actualHours(for: date, dataStore: dataStore)
        let expected = expectedHours(for: date, preferences: dataStore.preferences) * 3600
        return actual - expected
    }

    func weeklyOvertime(for weekOf: Date, dataStore: LocalDataStore) -> TimeInterval {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekOf)) else { return 0 }

        var totalOvertime: TimeInterval = 0
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            totalOvertime += overtime(for: day, dataStore: dataStore)
        }
        return totalOvertime
    }

    struct DailySummary {
        let date: Date
        let expectedHours: Double
        let actualHours: Double
        let breakHours: Double
        let overtimeHours: Double
        let isWorkDay: Bool
    }

    func weeklySummary(for weekOf: Date, dataStore: LocalDataStore) -> [DailySummary] {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekOf)) else { return [] }

        return (0..<7).compactMap { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { return nil }
            let actual = actualHours(for: day, dataStore: dataStore)
            let breaks = breakTime(for: day, dataStore: dataStore)
            let expected = expectedHours(for: day, preferences: dataStore.preferences)
            let ot = overtime(for: day, dataStore: dataStore)
            let isWork = isWorkDay(day, preferences: dataStore.preferences)

            return DailySummary(
                date: day,
                expectedHours: expected,
                actualHours: actual / 3600,
                breakHours: breaks / 3600,
                overtimeHours: ot / 3600,
                isWorkDay: isWork
            )
        }
    }
}
