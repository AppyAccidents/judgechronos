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
                            .foregroundColor(AppTheme.Colors.secondary)
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
                .background(AppTheme.Colors.subtleSurface)
                .cornerRadius(6)
            }

            Divider()

            if let error = dataSource.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(AppTheme.Colors.statusWarning)
            }

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
    @Published var lastError: String?
    
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
            Task { @MainActor in
                self?.checkCurrentApp()
            }
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
                await MainActor.run {
                    events = []
                    lastError = "Private mode is enabled. Activity tracking is paused."
                }
                return
            }
            do {
                try await dataStore.performIncrementalImport()
                let startOfDay = Calendar.current.startOfDay(for: Date())
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
                var raw = dataStore.events(from: startOfDay, to: endOfDay)
                if dataStore.preferences.calendarIntegrationEnabled, CalendarService.shared.hasAccess {
                    let calendarEvents = try CalendarService.shared.fetchEvents(
                        from: startOfDay,
                        to: endOfDay
                    )
                    let meetingsCategoryId = dataStore.addCategoryIfNeeded(name: "Meetings", color: AppTheme.Colors.secondary)
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
                await MainActor.run {
                    events = categorized
                    if categorized.isEmpty, dataStore.rawEvents.isEmpty, dataStore.sessions.isEmpty {
                        lastError = "No sessions imported yet. Press Refresh after granting Full Disk Access."
                    } else {
                        lastError = nil
                    }
                }
            } catch KnowledgeCReaderError.databaseNotFound(let searchedPaths) {
                _ = searchedPaths
                await MainActor.run {
                    events = []
                    lastError = "Setup required: grant Full Disk Access, relaunch Judge Chronos, then refresh."
                }
            } catch KnowledgeCReaderError.permissionDenied(let path) {
                _ = path
                await MainActor.run {
                    events = []
                    lastError = "Full Disk Access required. Enable access in Privacy & Security, relaunch, then refresh."
                }
            } catch {
                await MainActor.run {
                    events = []
                    lastError = "Unable to load activity data."
                }
            }
        }
    }
}
