import SwiftUI

@main
struct Judge_ChronosApp: App {
    @StateObject private var dataStore = LocalDataStore.shared
    @StateObject private var viewModel = ActivityViewModel()

    init() {
        let store = LocalDataStore.shared
        // In SwiftUI App lifecycle, StateObject init is tricky if trying to inject self.
        // But here we just use the shared instance.
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Judge Chronos") {
                    openAboutWindow()
                }
            }
        }
        MenuBarExtra("Judge Chronos", systemImage: "hourglass") {
            MenuBarView()
                .environmentObject(dataStore)
                .environmentObject(viewModel)
        }
    }
    
    private func openAboutWindow() {
        let aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        aboutWindow.title = "About Judge Chronos"
        aboutWindow.center()
        aboutWindow.contentView = NSHostingView(rootView: AboutView())
        aboutWindow.makeKeyAndOrderFront(nil)
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
