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

    @State private var showFocusPicker = false
    @State private var selectedFocusCategory: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Stats
            HStack {
                VStack(alignment: .leading) {
                    Text("Today")
                        .font(.headline)
                    Text(Formatting.formatDuration(totalTracked))
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Spacer()
                
                // Focus State
                if let session = dataStore.activeFocusSession() {
                    VStack(alignment: .trailing) {
                        Text("Focus Mode")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(dataStore.categoryName(for: session.categoryId))
                            .font(.headline)
                        Button("Stop") {
                            dataStore.endActiveFocusSession()
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button(action: { showFocusPicker.toggle() }) {
                        Label("Start Focus", systemImage: "target")
                    }
                    .controlSize(.small)
                    .popover(isPresented: $showFocusPicker) {
                        focusPicker
                    }
                }
            }
            
            Divider()
            
            // Current App
            if let current = dataSource.currentApp {
                HStack {
                    if let icon = dataSource.currentAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "app")
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    
                    Text(current)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    if let start = dataSource.currentAppStart {
                        Text(Formatting.formatDuration(now.timeIntervalSince(start)))
                            .font(.callout)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }

            Divider()

            Text("Top Apps")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                ForEach(Array(topApps.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.0)
                            .lineLimit(1)
                        Spacer()
                        Text(Formatting.formatDuration(item.1))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("Refresh") {
                    dataSource.refresh(dataStore: dataStore)
                    viewModel.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Spacer()
                
                Button("Open Judge Chronos") {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            dataSource.refresh(dataStore: dataStore)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { time in
            now = time
           // Only refresh full stats every minute or so, but update UI timer every second
           if Int(time.timeIntervalSince1970) % 60 == 0 {
               dataSource.refresh(dataStore: dataStore)
           }
        }
    }
    
    private var focusPicker: some View {
        VStack(spacing: 12) {
            Text("Start Focus Session")
                .font(.headline)
            
            Picker("Category", selection: $selectedFocusCategory) {
                Text("Select...").tag(UUID?.none)
                ForEach(dataStore.categories) { category in
                    Text(category.name).tag(category.id as UUID?)
                }
            }
            .labelsHidden()
            
            HStack {
                Button("25m") { startFocus(25) }
                Button("45m") { startFocus(45) }
                Button("60m") { startFocus(60) }
            }
        }
        .padding()
        .frame(width: 200)
    }
    
    private func startFocus(_ minutes: Int) {
        guard let savedId = selectedFocusCategory ?? dataStore.categories.first?.id else { return }
        dataStore.startFocusSession(durationMinutes: minutes, categoryId: savedId)
        showFocusPicker = false
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
    @Published var currentApp: String?
    @Published var currentAppStart: Date?
    @Published var currentAppIcon: NSImage?
    
    private let database = ActivityDatabase()
    private var workspaceObserver: NSObjectProtocol?

    init() {
        setupObserver()
        checkCurrentApp()
    }
    
    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    private func setupObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkCurrentApp()
        }
    }
    
    private func checkCurrentApp() {
        if let app = NSWorkspace.shared.frontmostApplication {
            if app.localizedName != currentApp {
                currentApp = app.localizedName
                currentAppStart = Date()
                currentAppIcon = app.icon
            }
        }
    }

    func refresh(dataStore: LocalDataStore) {
        checkCurrentApp()
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
