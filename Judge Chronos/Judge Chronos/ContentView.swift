import AppKit
import Charts
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable {
    case timeline
    case categories
    case rules
    case reports
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timeline: return "Timeline"
        case .categories: return "Categories"
        case .rules: return "Rules"
        case .reports: return "Reports"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: return "clock"
        case .categories: return "tag"
        case .rules: return "line.3.horizontal.decrease.circle"
        case .reports: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

struct ActivityGroupKey: Hashable {
    let appName: String
    let windowTitle: String?

    var displayName: String {
        if let windowTitle, !windowTitle.isEmpty {
            return "\(appName) — \(windowTitle)"
        }
        return appName
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .timeline
    @EnvironmentObject private var dataStore: LocalDataStore
    @EnvironmentObject private var viewModel: ActivityViewModel
    @State private var showingOnboardingFlow: Bool = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.label, systemImage: item.systemImage)
                    .tag(item as SidebarItem?)
            }
            .navigationTitle("Judge Chronos")
        } detail: {
            switch selection ?? .timeline {
            case .timeline:
                TimelineView()
            case .categories:
                CategoriesView()
            case .rules:
                RulesView()
            case .reports:
                ReportsView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .sheet(isPresented: $showingOnboardingFlow) {
            OnboardingFlowView(isPresented: $showingOnboardingFlow)
                .environmentObject(dataStore)
        }
        .onAppear {
            if !dataStore.preferences.hasCompletedOnboarding {
                showingOnboardingFlow = true
            }
        }
    }
}

struct TimelineView: View {
    @EnvironmentObject private var viewModel: ActivityViewModel
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var searchText: String = ""
    @State private var showingDailyReview: Bool = false
    @State private var showingFocusSession: Bool = false

    private var filteredEvents: [ActivityEvent] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.events }
        let query = trimmed.lowercased()
        return viewModel.events.filter { event in
            let categoryName = dataStore.categoryName(for: event.categoryId).lowercased()
            let app = event.appName.lowercased()
            let title = event.windowTitle?.lowercased() ?? ""
            return app.contains(query) || categoryName.contains(query) || title.contains(query)
        }
    }

    private var groupedByDay: [(Date, [ActivityEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { event in
            Calendar.current.startOfDay(for: event.startTime)
        }
        return grouped.map { (key: $0.key, value: $0.value.sorted { $0.startTime < $1.startTime }) }
            .sorted { $0.0 < $1.0 }
    }

    private func groupedByTask(_ events: [ActivityEvent]) -> [(ActivityGroupKey, [ActivityEvent])] {
        let grouped = Dictionary(grouping: events) { event in
            ActivityGroupKey(appName: event.appDisplayName, windowTitle: event.windowTitle)
        }
        return grouped.map { (key: $0.key, value: $0.value) }
            .sorted { lhs, rhs in
                let lhsStart = lhs.value.first?.startTime ?? .distantPast
                let rhsStart = rhs.value.first?.startTime ?? .distantPast
                return lhsStart < rhsStart
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusHeaderView()

            if dataStore.preferences.privateModeEnabled {
                PrivateModeBannerView()
            }

            if viewModel.showingOnboarding {
                OnboardingCardView()
            }

            searchBar
            dateRangePicker

            if case .unavailable(let message) = viewModel.aiAvailability {
                Text("Apple Intelligence unavailable: \(message)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if viewModel.isLoading {
                ProgressView("Loading activity...")
                    .padding(.top, 12)
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            } else if viewModel.events.isEmpty {
                EmptyStateView()
                    .padding(.top, 8)
            } else {
                List {
                    ForEach(groupedByDay, id: \.0) { day, eventsForDay in
                        Section(header: dayHeader(for: day)) {
                            ForEach(groupedByTask(eventsForDay), id: \.0) { groupKey, events in
                                VStack(alignment: .leading, spacing: 6) {
                                    sectionHeader(for: groupKey, events: events)
                                    ForEach(events) { event in
                                        TimelineRow(event: event)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .toolbar {
            ToolbarItemGroup {
                Button("Refresh") {
                    viewModel.refresh()
                }
                Button("Daily Review") {
                    showingDailyReview = true
                }
                .disabled(viewModel.events.isEmpty || viewModel.rangeEnabled)
                Button("Focus Session") {
                    showingFocusSession = true
                }
                Button("Export CSV") {
                    exportCSV()
                }
                Button("AI Suggest") {
                    viewModel.suggestCategoriesFromRecent()
                }
                .disabled(!isAIAvailable)
            }
        }
        .navigationTitle("Timeline")
        .onAppear {
            viewModel.refresh()
            viewModel.refreshAIAvailability()
        }
        .onReceive(dataStore.objectWillChange) { _ in
            viewModel.reapplyCategories()
        }
        .sheet(isPresented: $showingDailyReview) {
            DailyReviewView(events: viewModel.events, isPresented: $showingDailyReview)
                .environmentObject(dataStore)
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingFocusSession) {
            FocusSessionView(isPresented: $showingFocusSession)
                .environmentObject(dataStore)
        }
    }

    private var searchBar: some View {
        HStack {
            TextField("Search app, category, keyword", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
            if !searchText.isEmpty {
                Button("Clear") {
                    searchText = ""
                }
            }
            Spacer()
        }
    }

    private var dateRangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $viewModel.rangeEnabled) {
                Text("Single day").tag(false)
                Text("Date range").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: viewModel.rangeEnabled) { _, _ in
                viewModel.refresh()
            }

            if viewModel.rangeEnabled {
                HStack(spacing: 12) {
                    DatePicker("Start", selection: $viewModel.rangeStartDate, displayedComponents: .date)
                    DatePicker("End", selection: $viewModel.rangeEndDate, displayedComponents: .date)
                }
                .onChange(of: viewModel.rangeStartDate) { _, _ in viewModel.refresh() }
                .onChange(of: viewModel.rangeEndDate) { _, _ in viewModel.refresh() }
            } else {
                DatePicker("Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .onChange(of: viewModel.selectedDate) { _, _ in
                        viewModel.refresh()
                    }
            }
        }
    }

    private var isAIAvailable: Bool {
        if case .available = viewModel.aiAvailability {
            return true
        }
        return false
    }

    private func sectionHeader(for groupKey: ActivityGroupKey, events: [ActivityEvent]) -> some View {
        let total = events.reduce(0) { $0 + $1.duration }
        return HStack {
            Text(groupKey.displayName)
                .font(.headline)
            Spacer()
            Text(Formatting.formatDuration(total))
                .foregroundColor(.secondary)
        }
    }

    private func dayHeader(for date: Date) -> some View {
        Text(date.formatted(date: .abbreviated, time: .omitted))
            .font(.headline)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "judge-chronos-\(formattedDateForFilename()).csv"
        panel.canCreateDirectories = true
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let csv = CSVExporter.export(events: viewModel.events, dataStore: dataStore)
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // ignored; export errors surface in Reports view
            }
        }
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if viewModel.rangeEnabled {
            let normalized = viewModel.normalizedRange()
            let start = formatter.string(from: normalized.start)
            let end = formatter.string(from: normalized.end)
            return "\(start)_to_\(end)"
        }
        return formatter.string(from: viewModel.selectedDate)
    }
}

struct StatusHeaderView: View {
    @EnvironmentObject private var viewModel: ActivityViewModel
    @EnvironmentObject private var dataStore: LocalDataStore

    var body: some View {
        HStack(spacing: 12) {
            Label(statusText, systemImage: statusIcon)
                .font(.subheadline)
                .foregroundColor(statusColor)
            if let session = dataStore.activeFocusSession() {
                Text("Focus: \(dataStore.categoryName(for: session.categoryId)) until \(Formatting.formatTime(session.endTime))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if let lastRefresh = viewModel.lastRefresh {
                Text("Last refresh: \(Formatting.formatTime(lastRefresh))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var statusText: String {
        if dataStore.preferences.privateModeEnabled {
            return "Private mode enabled"
        }
        if viewModel.showingOnboarding {
            return "Needs Full Disk Access"
        }
        if viewModel.errorMessage != nil {
            return "Error loading activity"
        }
        return "Ready"
    }

    private var statusIcon: String {
        if dataStore.preferences.privateModeEnabled {
            return "eye.slash"
        }
        if viewModel.showingOnboarding {
            return "exclamationmark.triangle"
        }
        if viewModel.errorMessage != nil {
            return "exclamationmark.triangle"
        }
        return "checkmark.seal"
    }

    private var statusColor: Color {
        if dataStore.preferences.privateModeEnabled { return .orange }
        if viewModel.showingOnboarding { return .orange }
        if viewModel.errorMessage != nil { return .red }
        return .green
    }
}

struct PrivateModeBannerView: View {
    var body: some View {
        HStack {
            Image(systemName: "eye.slash")
            Text("Private mode is on. Activity tracking and reports are paused.")
            Spacer()
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }
}

struct OnboardingCardView: View {
    var body: some View {
        GroupBox("Grant Full Disk Access") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Judge Chronos needs Full Disk Access to read your activity data.")
                Text("If the toggle is disabled, unlock System Settings and move the app to /Applications.")
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button("Grant Full Disk Access") {
                        openFullDiskAccessSettings()
                    }
                    Button("Reveal App in Finder") {
                        revealAppInFinder()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

struct OnboardingFlowView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @Binding var isPresented: Bool
    @State private var step: Int = 0
    @State private var workStart: Date = Date()
    @State private var workEnd: Date = Date()
    @State private var enablePrivateMode: Bool = false
    @State private var exclusionPattern: String = ""
    @State private var selectedCategories: Set<String> = []
    @State private var didLoad: Bool = false

    private let suggestedCategories = [
        "Deep Work",
        "Meetings",
        "Communication",
        "Research",
        "Admin",
        "Social",
        "Break"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Judge Chronos")
                .font(.title2)
            Text("Let’s set up your day so tracking feels effortless.")
                .foregroundColor(.secondary)

            TabView(selection: $step) {
                workHoursStep
                    .tag(0)
                privacyStep
                    .tag(1)
                categoriesStep
                    .tag(2)
            }
            .tabViewStyle(.page)

            HStack {
                Button("Back") {
                    step = max(0, step - 1)
                }
                .disabled(step == 0)

                Spacer()

                if step < 2 {
                    Button("Next") {
                        step = min(2, step + 1)
                    }
                } else {
                    Button("Finish") {
                        completeOnboarding()
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .onAppear {
            if !didLoad {
                loadDefaults()
                didLoad = true
            }
        }
    }

    private var workHoursStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Work hours")
                .font(.headline)
            Text("Set your typical working hours.")
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                DatePicker("Start", selection: $workStart, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $workEnd, displayedComponents: .hourAndMinute)
            }
        }
        .padding(.top, 8)
    }

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Privacy")
                .font(.headline)
            Text("Control what is tracked and when.")
                .foregroundColor(.secondary)

            Toggle("Enable Private Mode (pause tracking)", isOn: $enablePrivateMode)

            HStack {
                TextField("Exclude apps containing…", text: $exclusionPattern)
                Button("Add") {
                    dataStore.addExclusion(pattern: exclusionPattern)
                    exclusionPattern = ""
                }
                .disabled(exclusionPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !dataStore.exclusions.isEmpty {
                Text("Current exclusions: \(dataStore.exclusions.map { $0.pattern }.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Starter categories")
                .font(.headline)
            Text("Pick a few categories to get going.")
                .foregroundColor(.secondary)

            ForEach(suggestedCategories, id: \.self) { name in
                Toggle(name, isOn: Binding(
                    get: { selectedCategories.contains(name) },
                    set: { isSelected in
                        if isSelected {
                            selectedCategories.insert(name)
                        } else {
                            selectedCategories.remove(name)
                        }
                    }
                ))
            }
        }
        .padding(.top, 8)
    }

    private func loadDefaults() {
        let prefs = dataStore.preferences
        workStart = dateForTime(prefs.workDayStart)
        workEnd = dateForTime(prefs.workDayEnd)
        enablePrivateMode = prefs.privateModeEnabled
        selectedCategories = Set(suggestedCategories.prefix(4))
    }

    private func completeOnboarding() {
        let formatter = timeFormatter()
        let startString = formatter.string(from: workStart)
        let endString = formatter.string(from: workEnd)
        dataStore.updatePreferences { prefs in
            prefs.workDayStart = startString
            prefs.workDayEnd = endString
            prefs.privateModeEnabled = enablePrivateMode
            prefs.hasCompletedOnboarding = true
        }
        for name in selectedCategories {
            _ = dataStore.addCategoryIfNeeded(name: name, color: .blue)
        }
    }

    private func dateForTime(_ value: String) -> Date {
        let parts = value.split(separator: ":")
        let hour = Int(parts.first ?? "9") ?? 9
        let minute = Int(parts.dropFirst().first ?? "0") ?? 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}

struct TimelineRow: View {
    @EnvironmentObject private var viewModel: ActivityViewModel
    @EnvironmentObject private var dataStore: LocalDataStore

    let event: ActivityEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Start: \(Formatting.formatTime(event.startTime))")
                Spacer()
                Text("Duration: \(Formatting.formatDuration(event.duration))")
                    .foregroundColor(.secondary)
            }

            if let windowTitle = event.windowTitle {
                Text("Window: \(windowTitle)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                if event.isIdle {
                    Text("Idle")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Category", selection: assignmentBinding(for: event)) {
                        Text("Auto (rules)").tag(UUID?.none)
                        ForEach(dataStore.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)

                    let ruleCategory = dataStore.ruleCategoryForApp(event.appName)
                    if dataStore.assignmentForEvent(event) == nil, let ruleCategory {
                        Text("Auto: \(dataStore.categoryName(for: ruleCategory))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                aiSuggestionView
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private var aiSuggestionView: some View {
        Group {
            if event.isIdle {
                EmptyView()
            } else if let suggestion = viewModel.suggestions[event.eventKey] {
                HStack(spacing: 8) {
                    Text("AI: \(suggestion.category)")
                        .font(.footnote)
                    Button("Apply") {
                        viewModel.applySuggestion(for: event)
                    }
                    Button("Dismiss") {
                        viewModel.dismissSuggestion(for: event)
                    }
                }
                if let rationale = suggestion.rationale, !rationale.isEmpty {
                    Text(rationale)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else if viewModel.isSuggestingEvents.contains(event.eventKey) {
                ProgressView()
                    .controlSize(.small)
            } else if let error = viewModel.suggestionErrors[event.eventKey] {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Button("Suggest") {
                    viewModel.suggestCategory(for: event)
                }
                .disabled(!isAIAvailable)
            }
        }
    }

    private var isAIAvailable: Bool {
        if case .available = viewModel.aiAvailability {
            return true
        }
        return false
    }

    private func assignmentBinding(for event: ActivityEvent) -> Binding<UUID?> {
        Binding(
            get: { dataStore.assignmentForEvent(event) },
            set: { newValue in
                viewModel.updateCategory(for: event, categoryId: newValue)
            }
        )
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No activity found for this day.")
                .font(.headline)
            Text("If you just granted Full Disk Access, press Refresh. Otherwise, your Mac may not have recorded app usage yet.")
                .foregroundColor(.secondary)
        }
    }
}

struct DailyReviewView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @EnvironmentObject private var viewModel: ActivityViewModel
    @State private var showOnlyUncategorized: Bool = true
    @Binding var isPresented: Bool

    let events: [ActivityEvent]

    private var reviewEvents: [ActivityEvent] {
        events.filter { event in
            guard !event.isIdle else { return false }
            if showOnlyUncategorized {
                return event.categoryId == nil
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Review")
                    .font(.title2)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
            }

            Toggle("Show only uncategorized", isOn: $showOnlyUncategorized)

            if reviewEvents.isEmpty {
                Text("All caught up for this day.")
                    .foregroundColor(.secondary)
            } else {
                List(reviewEvents) { event in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.appDisplayName)
                            Text("\(Formatting.formatTime(event.startTime)) • \(Formatting.formatDuration(event.duration))")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("Category", selection: assignmentBinding(for: event)) {
                            Text("Uncategorized").tag(UUID?.none)
                            ForEach(dataStore.categories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }

    private func assignmentBinding(for event: ActivityEvent) -> Binding<UUID?> {
        Binding(
            get: { dataStore.assignmentForEvent(event) },
            set: { newValue in
                viewModel.updateCategory(for: event, categoryId: newValue)
            }
        )
    }
}

struct FocusSessionView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @Binding var isPresented: Bool
    @State private var selectedCategoryId: UUID? = nil
    @State private var duration: Int = 25

    private let durations = [25, 50, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Focus Session")
                    .font(.title2)
                Spacer()
                Button("Close") {
                    isPresented = false
                }
            }

            if let session = dataStore.activeFocusSession() {
                Text("Active session: \(dataStore.categoryName(for: session.categoryId))")
                Text("Ends at \(Formatting.formatTime(session.endTime))")
                    .foregroundColor(.secondary)
                Button("End Session Now") {
                    dataStore.endActiveFocusSession()
                }
            } else {
                Picker("Category", selection: $selectedCategoryId) {
                    Text("Select category").tag(UUID?.none)
                    ForEach(dataStore.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }

                Picker("Duration", selection: $duration) {
                    ForEach(durations, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)

                Button("Start Focus Session") {
                    guard let categoryId = selectedCategoryId else { return }
                    dataStore.startFocusSession(durationMinutes: duration, categoryId: categoryId)
                    isPresented = false
                }
                .disabled(selectedCategoryId == nil)
            }
        }
        .padding(20)
        .frame(width: 420, height: 280)
    }
}

struct CategoriesView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @EnvironmentObject private var viewModel: ActivityViewModel
    @State private var newCategoryName: String = ""
    @State private var newCategoryColor: Color = .blue

    var body: some View {
        List {
            Section("Add Category") {
                TextField("Category name", text: $newCategoryName)
                ColorPicker("Color", selection: $newCategoryColor)
                Button("Add") {
                    guard !newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    dataStore.addCategory(name: newCategoryName, color: newCategoryColor)
                    newCategoryName = ""
                    newCategoryColor = .blue
                }
            }

            Section("Categories") {
                if dataStore.categories.isEmpty {
                    Text("No categories yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(dataStore.categories) { category in
                        CategoryRow(category: category)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let category = dataStore.categories[index]
                            dataStore.deleteCategory(category)
                        }
                    }
                }
            }

            Section("AI Suggestions") {
                if case .unavailable(let message) = viewModel.aiAvailability {
                    Text("Apple Intelligence unavailable: \(message)")
                        .foregroundColor(.secondary)
                }
                if viewModel.isSuggestingCategories {
                    ProgressView("Thinking...")
                } else if viewModel.categorySuggestions.isEmpty {
                    Text("No suggestions yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.categorySuggestions, id: \.self) { suggestion in
                        HStack {
                            Text(suggestion)
                            Spacer()
                            Button("Add") {
                                viewModel.applyCategorySuggestion(suggestion)
                            }
                        }
                    }
                }
                Button("Suggest Categories from Recent Activity") {
                    viewModel.suggestCategoriesFromRecent()
                }
                .disabled(!isAIAvailable)
            }
        }
        .padding()
        .toolbar {
            ToolbarItemGroup {
                Button("Suggest Categories") {
                    viewModel.suggestCategoriesFromRecent()
                }
                .disabled(!isAIAvailable)
            }
        }
        .navigationTitle("Categories")
    }

    private var isAIAvailable: Bool {
        if case .available = viewModel.aiAvailability {
            return true
        }
        return false
    }
}

struct CategoryRow: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var name: String
    @State private var color: Color

    let category: Category

    init(category: Category) {
        self.category = category
        _name = State(initialValue: category.name)
        _color = State(initialValue: Color(hex: category.colorHex) ?? .blue)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $name)
            ColorPicker("Color", selection: $color)
                .frame(width: 180)
            Button("Save") {
                dataStore.updateCategory(category, name: name, color: color)
            }
        }
    }
}

struct RulesView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var pattern: String = ""
    @State private var selectedCategoryId: UUID? = nil

    var body: some View {
        List {
            Section("Add Rule") {
                TextField("App name contains", text: $pattern)
                Picker("Category", selection: $selectedCategoryId) {
                    Text("Select category").tag(UUID?.none)
                    ForEach(dataStore.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                Button("Add") {
                    guard let categoryId = selectedCategoryId,
                          !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    dataStore.addRule(pattern: pattern, categoryId: categoryId)
                    pattern = ""
                }
            }

            Section("Rules") {
                if dataStore.rules.isEmpty {
                    Text("No rules yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(dataStore.rules) { rule in
                        HStack {
                            Text("Contains: \(rule.pattern)")
                            Spacer()
                            Text(dataStore.categoryName(for: rule.categoryId))
                                .foregroundColor(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let rule = dataStore.rules[index]
                            dataStore.deleteRule(rule)
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Rules")
    }
}

struct ReportsView: View {
    @EnvironmentObject private var viewModel: ActivityViewModel
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var exportStatus: String? = nil
    @State private var isLoadingWeeklyRecap: Bool = false

    private var totals: [(String, Double, Color)] {
        let grouped = Dictionary(grouping: viewModel.events) { event in
            if event.isIdle { return "Idle" }
            return dataStore.categoryName(for: event.categoryId)
        }
        return grouped.map { name, events in
            let total = events.reduce(0) { $0 + $1.duration }
            let color = name == "Idle" ? Color.gray : dataStore.categoryColor(for: events.first?.categoryId)
            return (name, total, color)
        }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reportSubtitle)
                .foregroundColor(.secondary)

            dateRangePicker

            weeklyRecapSection

            goalsProgressSection

            if totals.isEmpty {
                EmptyStateView()
            } else {
                Chart {
                    ForEach(Array(totals.enumerated()), id: \.offset) { _, item in
                        BarMark(
                            x: .value("Category", item.0),
                            y: .value("Minutes", item.1 / 60)
                        )
                        .foregroundStyle(item.2)
                    }
                }
                .frame(height: 240)

                List {
                    ForEach(Array(totals.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.0)
                            Spacer()
                            Text(Formatting.formatDuration(item.1))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(minHeight: 200)
            }

            HStack {
                Button("Export CSV") {
                    exportCSV()
                }
                Button("Export JSON") {
                    exportJSON()
                }
                if let exportStatus {
                    Text(exportStatus)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .navigationTitle("Reports")
    }

    private var dateRangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $viewModel.rangeEnabled) {
                Text("Single day").tag(false)
                Text("Date range").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: viewModel.rangeEnabled) { _, _ in
                viewModel.refresh()
            }

            if viewModel.rangeEnabled {
                HStack(spacing: 12) {
                    DatePicker("Start", selection: $viewModel.rangeStartDate, displayedComponents: .date)
                    DatePicker("End", selection: $viewModel.rangeEndDate, displayedComponents: .date)
                }
                .onChange(of: viewModel.rangeStartDate) { _, _ in viewModel.refresh() }
                .onChange(of: viewModel.rangeEndDate) { _, _ in viewModel.refresh() }
            } else {
                DatePicker("Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .onChange(of: viewModel.selectedDate) { _, _ in
                        viewModel.refresh()
                    }
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "judge-chronos-\(formattedDateForFilename()).csv"
        panel.canCreateDirectories = true
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let csv = CSVExporter.export(events: viewModel.events, dataStore: dataStore)
                try csv.write(to: url, atomically: true, encoding: .utf8)
                exportStatus = "Exported to \(url.lastPathComponent)"
            } catch {
                exportStatus = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "judge-chronos-\(formattedDateForFilename()).json"
        panel.canCreateDirectories = true
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let payload = JSONExporter.export(events: viewModel.events, dataStore: dataStore)
                try payload.write(to: url, atomically: true, encoding: .utf8)
                exportStatus = "Exported to \(url.lastPathComponent)"
            } catch {
                exportStatus = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func formattedDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if viewModel.rangeEnabled {
            let normalized = viewModel.normalizedRange()
            let start = formatter.string(from: normalized.start)
            let end = formatter.string(from: normalized.end)
            return "\(start)_to_\(end)"
        }
        return formatter.string(from: viewModel.selectedDate)
    }

    private var reportSubtitle: String {
        if viewModel.rangeEnabled {
            let normalized = viewModel.normalizedRange()
            let start = normalized.start.formatted(date: .abbreviated, time: .omitted)
            let end = normalized.end.formatted(date: .abbreviated, time: .omitted)
            return "Totals for \(start) – \(end)."
        }
        return "Daily totals for \(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))."
    }

    private var weeklyRecapSection: some View {
        GroupBox("Weekly Recap") {
            VStack(alignment: .leading, spacing: 8) {
                if !dataStore.preferences.weeklyRecapEnabled {
                    Text("Weekly recap is disabled in Settings.")
                        .foregroundColor(.secondary)
                } else if let recap = viewModel.weeklyRecap {
                    let start = recap.startDate.formatted(date: .abbreviated, time: .omitted)
                    let end = recap.endDate.formatted(date: .abbreviated, time: .omitted)
                    Text("Week of \(start) – \(end)")
                        .font(.subheadline)
                    ForEach(Array(recap.topCategories.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(dataStore.categoryName(for: entry.0))
                            Spacer()
                            Text("\(entry.1) min")
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("Change vs last week: \(recap.deltaMinutes) min")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Text("Generate a quick summary of this week’s activity.")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button(isLoadingWeeklyRecap ? "Loading..." : "Generate Weekly Recap") {
                        isLoadingWeeklyRecap = true
                        Task {
                            await viewModel.loadWeeklyRecap()
                            await MainActor.run { isLoadingWeeklyRecap = false }
                        }
                    }
                    .disabled(isLoadingWeeklyRecap || !dataStore.preferences.weeklyRecapEnabled)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var goalsProgressSection: some View {
        GroupBox("Goals") {
            VStack(alignment: .leading, spacing: 8) {
                if dataStore.goals.isEmpty {
                    Text("No goals yet. Add one in Settings.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(dataStore.goals) { goal in
                        let spent = Int(viewModel.events.filter { $0.categoryId == goal.categoryId }.reduce(0) { $0 + $1.duration } / 60)
                        let name = dataStore.categoryName(for: goal.categoryId)
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(spent) / \(goal.minutesPerDay) min")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var viewModel: ActivityViewModel
    @EnvironmentObject private var dataStore: LocalDataStore
    @State private var exclusionPattern: String = ""
    @State private var goalCategoryId: UUID? = nil
    @State private var goalMinutes: String = "60"

    var body: some View {
        Form {
            Section("Full Disk Access") {
                Text("Judge Chronos reads your activity data from the system database.")
                Text("If the toggle is disabled, unlock System Settings and move the app to /Applications.")
                    .foregroundColor(.secondary)
                HStack(spacing: 12) {
                    Button("Open System Settings") {
                        openFullDiskAccessSettings()
                    }
                    Button("Reveal App in Finder") {
                        revealAppInFinder()
                    }
                }
            }

            Section("Work Day") {
                DatePicker("Start", selection: Binding(
                    get: { dateForTime(dataStore.preferences.workDayStart) },
                    set: { newValue in
                        dataStore.updatePreferences { $0.workDayStart = timeFormatter().string(from: newValue) }
                    }
                ), displayedComponents: .hourAndMinute)

                DatePicker("End", selection: Binding(
                    get: { dateForTime(dataStore.preferences.workDayEnd) },
                    set: { newValue in
                        dataStore.updatePreferences { $0.workDayEnd = timeFormatter().string(from: newValue) }
                        Task {
                            if dataStore.preferences.goalNudgesEnabled {
                                await NotificationManager.scheduleGoalNudge(time: newValue)
                            }
                        }
                    }
                ), displayedComponents: .hourAndMinute)
            }

            Section("Apple Intelligence") {
                AIStatusView()
                Button("Refresh AI Status") {
                    viewModel.refreshAIAvailability()
                }
            }

            Section("Privacy") {
                Toggle("Private mode (pause tracking)", isOn: Binding(
                    get: { dataStore.preferences.privateModeEnabled },
                    set: { newValue in
                        dataStore.updatePreferences { $0.privateModeEnabled = newValue }
                        viewModel.refresh()
                    }
                ))

                HStack {
                    TextField("Exclude apps containing…", text: $exclusionPattern)
                    Button("Add") {
                        dataStore.addExclusion(pattern: exclusionPattern)
                        exclusionPattern = ""
                    }
                    .disabled(exclusionPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if dataStore.exclusions.isEmpty {
                    Text("No exclusions yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(dataStore.exclusions) { rule in
                        HStack {
                            Text(rule.pattern)
                            Spacer()
                            Button("Remove") {
                                dataStore.deleteExclusion(rule)
                                viewModel.refresh()
                            }
                        }
                    }
                }
            }

            Section("Daily Review") {
                Toggle("Enable daily review reminder", isOn: Binding(
                    get: { dataStore.preferences.reviewReminderEnabled },
                    set: { newValue in
                        dataStore.updatePreferences { $0.reviewReminderEnabled = newValue }
                        Task {
                            if newValue {
                                await NotificationManager.scheduleDailyReview(time: dateForTime(dataStore.preferences.reviewReminderTime))
                            } else {
                                await NotificationManager.clearDailyReview()
                            }
                        }
                    }
                ))
                DatePicker("Reminder time", selection: Binding(
                    get: { dateForTime(dataStore.preferences.reviewReminderTime) },
                    set: { newValue in
                        dataStore.updatePreferences { $0.reviewReminderTime = timeFormatter().string(from: newValue) }
                        Task {
                            if dataStore.preferences.reviewReminderEnabled {
                                await NotificationManager.scheduleDailyReview(time: newValue)
                            }
                        }
                    }
                ), displayedComponents: .hourAndMinute)
            }

            Section("Goals") {
                Picker("Category", selection: $goalCategoryId) {
                    Text("Select category").tag(UUID?.none)
                    ForEach(dataStore.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                TextField("Minutes per day", text: $goalMinutes)
                    .frame(width: 120)
                Button("Add Goal") {
                    guard let categoryId = goalCategoryId,
                          let minutes = Int(goalMinutes), minutes > 0 else { return }
                    dataStore.addGoal(categoryId: categoryId, minutesPerDay: minutes)
                }

                Toggle("Enable goal nudges", isOn: Binding(
                    get: { dataStore.preferences.goalNudgesEnabled },
                    set: { newValue in
                        dataStore.updatePreferences { $0.goalNudgesEnabled = newValue }
                        Task {
                            if newValue {
                                await NotificationManager.scheduleGoalNudge(time: dateForTime(dataStore.preferences.workDayEnd))
                            } else {
                                await NotificationManager.clearGoalNudge()
                            }
                        }
                    }
                ))

                if dataStore.goals.isEmpty {
                    Text("No goals yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(dataStore.goals) { goal in
                        HStack {
                            Text(dataStore.categoryName(for: goal.categoryId))
                            Spacer()
                            Text("\(goal.minutesPerDay) min/day")
                                .foregroundColor(.secondary)
                            Button("Remove") {
                                dataStore.deleteGoal(goal)
                            }
                        }
                    }
                }
            }

            Section("Weekly Recap") {
                Toggle("Enable weekly story recap", isOn: Binding(
                    get: { dataStore.preferences.weeklyRecapEnabled },
                    set: { newValue in
                        dataStore.updatePreferences { $0.weeklyRecapEnabled = newValue }
                    }
                ))
            }

            Section("Integrations") {
                Toggle("Calendar/meeting integration", isOn: Binding(
                    get: { dataStore.preferences.calendarIntegrationEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                do {
                                    try await CalendarService.shared.requestAccess()
                                    await MainActor.run {
                                        dataStore.updatePreferences { $0.calendarIntegrationEnabled = true }
                                        viewModel.refresh()
                                    }
                                } catch {
                                    await MainActor.run {
                                        dataStore.updatePreferences { $0.calendarIntegrationEnabled = false }
                                    }
                                }
                            }
                        } else {
                            dataStore.updatePreferences { $0.calendarIntegrationEnabled = false }
                            viewModel.refresh()
                        }
                    }
                ))
                Toggle("Email summary (coming soon)", isOn: Binding(
                    get: { dataStore.preferences.emailSummaryEnabled },
                    set: { newValue in
                        dataStore.updatePreferences { $0.emailSummaryEnabled = newValue }
                    }
                ))
            }

            Section("Data & Backup") {
                Toggle("Back up data to iCloud (coming soon)", isOn: Binding(
                    get: { dataStore.preferences.iCloudBackupEnabled },
                    set: { newValue in
                        dataStore.updatePreferences { $0.iCloudBackupEnabled = newValue }
                    }
                ))
                Button("Reveal Local Data Folder") {
                    revealDataFolder()
                }
            }
        }
        .padding()
        .navigationTitle("Settings")
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func revealDataFolder() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let appURL = baseURL?.appendingPathComponent("JudgeChronos", isDirectory: true)
        if let appURL {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        }
    }

    private func dateForTime(_ value: String) -> Date {
        let parts = value.split(separator: ":")
        let hour = Int(parts.first ?? "9") ?? 9
        let minute = Int(parts.dropFirst().first ?? "0") ?? 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func timeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}

struct AIStatusView: View {
    @EnvironmentObject private var viewModel: ActivityViewModel

    var body: some View {
        switch viewModel.aiAvailability {
        case .available:
            Label("Apple Intelligence available", systemImage: "checkmark.seal")
                .foregroundColor(.green)
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Apple Intelligence unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text(message)
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
        }
    }
}

enum CSVExporter {
    @MainActor static func export(events: [ActivityEvent], dataStore: LocalDataStore) -> String {
        var lines: [String] = ["app_name,start_time,end_time,duration_seconds,category"]
        let formatter = ISO8601DateFormatter()
        for event in events {
            let category = event.isIdle ? "Idle" : dataStore.categoryName(for: event.categoryId)
            let start = formatter.string(from: event.startTime)
            let end = formatter.string(from: event.endTime)
            let duration = Int(event.duration)
            let row = [event.appName, start, end, String(duration), category]
                .map { escapeCSV($0) }
                .joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

enum JSONExporter {
    @MainActor static func export(events: [ActivityEvent], dataStore: LocalDataStore) -> String {
        struct ExportEvent: Codable {
            let appName: String
            let startTime: String
            let endTime: String
            let durationSeconds: Int
            let category: String
        }

        let formatter = ISO8601DateFormatter()
        let payload = events.map { event in
            ExportEvent(
                appName: event.appName,
                startTime: formatter.string(from: event.startTime),
                endTime: formatter.string(from: event.endTime),
                durationSeconds: Int(event.duration),
                category: event.isIdle ? "Idle" : dataStore.categoryName(for: event.categoryId)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

#Preview {
    let store = LocalDataStore()
    ContentView()
        .environmentObject(store)
        .environmentObject(ActivityViewModel(dataStore: store))
}
