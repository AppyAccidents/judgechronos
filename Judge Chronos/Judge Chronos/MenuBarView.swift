import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @EnvironmentObject private var viewModel: ActivityViewModel
    @StateObject private var dataSource = MenuBarDataSource()
    @State private var now: Date = Date()

    private var todayEvents: [ActivityEvent] {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return dataSource.events.filter { Calendar.current.isDate($0.startTime, inSameDayAs: startOfDay) }
    }

    private var topApps: [(String, TimeInterval)] {
        let grouped = Dictionary(grouping: todayEvents.filter { !$0.isIdle }) { $0.appDisplayName }
        return grouped.map { name, events in
            (name, events.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.1 > $1.1 }
        .prefix(3)
        .map { $0 }
    }

    private var topCategories: [(String, TimeInterval)] {
        let grouped = Dictionary(grouping: todayEvents.filter { !$0.isIdle }) { event in
            dataStore.categoryName(for: event.categoryId)
        }
        return grouped.map { name, events in
            (name, events.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.1 > $1.1 }
        .prefix(3)
        .map { $0 }
    }

    private var totalTracked: TimeInterval {
        todayEvents.filter { !$0.isIdle }.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            Text("Tracked: \(Formatting.formatDuration(totalTracked))")
                .font(.subheadline)

            if let session = dataStore.activeFocusSession() {
                Text("Focus: \(dataStore.categoryName(for: session.categoryId))")
                    .font(.footnote)
                Text("Ends at \(Formatting.formatTime(session.endTime))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Divider()

            Text("Top Apps")
                .font(.subheadline)
            ForEach(Array(topApps.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(Formatting.formatDuration(item.1))
                        .foregroundColor(.secondary)
                }
            }

            Text("Top Categories")
                .font(.subheadline)
                .padding(.top, 4)
            ForEach(Array(topCategories.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(Formatting.formatDuration(item.1))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Button("Refresh Now") {
                dataSource.refresh(dataStore: dataStore)
                viewModel.refresh()
            }
            Button("Open Judge Chronos") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            dataSource.refresh(dataStore: dataStore)
        }
        .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { time in
            now = time
            dataSource.refresh(dataStore: dataStore)
        }
    }
}

#Preview {
    let store = LocalDataStore()
    MenuBarView()
        .environmentObject(store)
        .environmentObject(ActivityViewModel(dataStore: store))
}

@MainActor
final class MenuBarDataSource: ObservableObject {
    @Published var events: [ActivityEvent] = []
    private let database = ActivityDatabase()

    func refresh(dataStore: LocalDataStore) {
        Task {
            guard !dataStore.preferences.privateModeEnabled else {
                await MainActor.run { events = [] }
                return
            }
            do {
                var raw = try database.fetchEvents(for: Date())
                if dataStore.preferences.calendarIntegrationEnabled, CalendarService.shared.hasAccess {
                    let calendarEvents = try CalendarService.shared.fetchEvents(
                        from: Calendar.current.startOfDay(for: Date()),
                        to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    )
                    let meetingsCategoryId = dataStore.addCategoryIfNeeded(name: "Meetings", color: .orange)
                    let meetingEvents = calendarEvents.map { event in
                        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = title?.isEmpty == false ? "Meeting — \(title!)" : "Meeting"
                        return ActivityEvent(
                            id: UUID(),
                            eventKey: ActivityEventKey.make(appName: name, startTime: event.startDate, endTime: event.endDate),
                            appName: name,
                            startTime: event.startDate,
                            endTime: event.endDate,
                            duration: event.endDate.timeIntervalSince(event.startDate),
                            categoryId: meetingsCategoryId,
                            isIdle: false,
                            source: .calendar
                        )
                    }
                    raw.append(contentsOf: meetingEvents)
                }
                let filtered = raw.filter { !dataStore.isExcluded(appName: $0.appName) }
                let categorized = dataStore.applyCategories(to: filtered)
                await MainActor.run { events = categorized }
            } catch {
                await MainActor.run { events = [] }
            }
        }
    }
}
