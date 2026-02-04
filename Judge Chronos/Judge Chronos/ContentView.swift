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

struct ContentView: View {
    @State private var selection: SidebarItem? = .timeline

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
    }
}

struct TimelineView: View {
    @EnvironmentObject private var viewModel: ActivityViewModel
    @EnvironmentObject private var dataStore: LocalDataStore

    private var groupedByDay: [(Date, [ActivityEvent])] {
        let grouped = Dictionary(grouping: viewModel.events) { event in
            Calendar.current.startOfDay(for: event.startTime)
        }
        return grouped.map { (key: $0.key, value: $0.value.sorted { $0.startTime < $1.startTime }) }
            .sorted { $0.0 < $1.0 }
    }

    private func groupedByApp(_ events: [ActivityEvent]) -> [(String, [ActivityEvent])] {
        let grouped = Dictionary(grouping: events) { $0.appName }
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

            if viewModel.showingOnboarding {
                OnboardingCardView()
            }

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
                            ForEach(groupedByApp(eventsForDay), id: \.0) { appName, events in
                                VStack(alignment: .leading, spacing: 6) {
                                    sectionHeader(for: appName, events: events)
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

    private func sectionHeader(for appName: String, events: [ActivityEvent]) -> some View {
        let total = events.reduce(0) { $0 + $1.duration }
        return HStack {
            Text(appName)
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

    var body: some View {
        HStack(spacing: 12) {
            Label(statusText, systemImage: statusIcon)
                .font(.subheadline)
                .foregroundColor(statusColor)
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
        if viewModel.showingOnboarding {
            return "Needs Full Disk Access"
        }
        if viewModel.errorMessage != nil {
            return "Error loading activity"
        }
        return "Ready"
    }

    private var statusIcon: String {
        if viewModel.showingOnboarding {
            return "exclamationmark.triangle"
        }
        if viewModel.errorMessage != nil {
            return "exclamationmark.triangle"
        }
        return "checkmark.seal"
    }

    private var statusColor: Color {
        if viewModel.showingOnboarding { return .orange }
        if viewModel.errorMessage != nil { return .red }
        return .green
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
}

struct SettingsView: View {
    @EnvironmentObject private var viewModel: ActivityViewModel

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

            Section("Apple Intelligence") {
                AIStatusView()
                Button("Refresh AI Status") {
                    viewModel.refreshAIAvailability()
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

#Preview {
    let store = LocalDataStore()
    ContentView()
        .environmentObject(store)
        .environmentObject(ActivityViewModel(dataStore: store))
}
