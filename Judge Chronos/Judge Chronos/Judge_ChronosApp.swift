import SwiftUI

@main
struct Judge_ChronosApp: App {
    @StateObject private var dataStore: LocalDataStore
    @StateObject private var viewModel: ActivityViewModel

    init() {
        let store = LocalDataStore()
        _dataStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: ActivityViewModel(dataStore: store))

        Task {
            if store.preferences.reviewReminderEnabled {
                await NotificationManager.scheduleDailyReview(time: Self.dateForTime(store.preferences.reviewReminderTime))
            }
            if store.preferences.goalNudgesEnabled {
                await NotificationManager.scheduleGoalNudge(time: Self.dateForTime(store.preferences.workDayEnd))
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(viewModel)
        }
        MenuBarExtra("Judge Chronos", systemImage: "hourglass") {
            MenuBarView()
                .environmentObject(dataStore)
                .environmentObject(viewModel)
        }
    }
}

private extension Judge_ChronosApp {
    static func dateForTime(_ value: String) -> Date {
        let parts = value.split(separator: ":")
        let hour = Int(parts.first ?? "9") ?? 9
        let minute = Int(parts.dropFirst().first ?? "0") ?? 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
