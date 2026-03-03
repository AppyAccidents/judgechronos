import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct ReportBuilderView: View {
    @EnvironmentObject private var dataStore: LocalDataStore
    
    // Report Configuration
    @State private var selectedTemplate: ReportTemplate = .timesheet
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var selectedProjectIds: Set<UUID> = []
    @State private var includeSubprojects = true
    @State private var groupBy: GroupingOption = .day
    @State private var companyName = ""
    @State private var clientName = ""
    @State private var notes = ""
    @State private var hourlyRate: String = ""
    @State private var taxRate: String = ""
    @State private var showBillableOnly = false
    
    // UI State
    @State private var isGenerating = false
    @State private var showingPreview = false
    @State private var generatedPDF: PDFDocument?
    @State private var showExportSheet = false
    @State private var exportData: Data?
    @State private var exportFormat: ExportFormat?
    @State private var showingExportSheet = false
    @State private var recentExports: [RecentExport] = []
    
    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF"
        case csv = "CSV (Excel)"
        case html = "HTML"
        
        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .csv: return "csv"
            case .html: return "html"
            }
        }
        
        var utType: UTType {
            switch self {
            case .pdf: return .pdf
            case .csv: return .commaSeparatedText
            case .html: return .html
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .font(.title2)
                Text("Report Builder")
                    .font(.title2)
                Spacer()
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Template Selection
                    TemplateSection(
                        selectedTemplate: $selectedTemplate
                    )
                    
                    // Date Range
                    DateRangeSection(
                        startDate: $startDate,
                        endDate: $endDate
                    )
                    
                    // Project Selection
                    ProjectSelectionSection(
                        projects: dataStore.projects,
                        selectedIds: $selectedProjectIds,
                        includeSubprojects: $includeSubprojects
                    )
                    
                    // Grouping
                    GroupingSection(
                        groupBy: $groupBy
                    )
                    
                    // Invoice Details (conditional)
                    if selectedTemplate == .invoice {
                        InvoiceDetailsSection(
                            companyName: $companyName,
                            clientName: $clientName,
                            hourlyRate: $hourlyRate,
                            taxRate: $taxRate,
                            notes: $notes,
                            showBillableOnly: $showBillableOnly
                        )
                    }
                    
                    // Preview Summary
                    PreviewSummarySection(
                        config: currentConfiguration(),
                        dataStore: dataStore
                    )
                }
                .padding()
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Preview") {
                    generatePreview()
                }
                .disabled(isGenerating)
                
                Spacer()
                
                Menu("Export") {
                    Button("Export as PDF") {
                        exportFormat = .pdf
                        generateExport()
                    }
                    Button("Export as CSV") {
                        exportFormat = .csv
                        generateExport()
                    }
                    Button("Export as HTML") {
                        exportFormat = .html
                        generateExport()
                    }
                }
                .disabled(isGenerating)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .sheet(isPresented: $showingPreview) {
            if let pdf = generatedPDF {
                PDFPreviewSheet(pdf: pdf)
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            if let data = exportData {
                ExportSheet(data: data, format: exportFormat ?? .pdf, config: currentConfiguration())
            }
        }
    }
    
    // MARK: - Configuration
    private func currentConfiguration() -> ReportConfiguration {
        ReportConfiguration(
            template: selectedTemplate,
            startDate: startDate,
            endDate: endDate,
            projectIds: Array(selectedProjectIds),
            includeSubprojects: includeSubprojects,
            groupBy: groupBy,
            companyName: companyName,
            companyLogo: nil,
            clientName: clientName,
            notes: notes,
            hourlyRate: Double(hourlyRate),
            taxRate: Double(taxRate),
            showBillableOnly: showBillableOnly
        )
    }
    
    // MARK: - Actions
    private func generatePreview() {
        isGenerating = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let config = currentConfiguration()
            let pdf = PDFReportGenerator.shared.generateReport(
                config: config,
                dataStore: dataStore
            )
            
            DispatchQueue.main.async {
                generatedPDF = pdf
                showingPreview = true
                isGenerating = false
            }
        }
    }
    
    private func generateExport() {
        guard let format = exportFormat else { return }
        isGenerating = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let config = currentConfiguration()
            var data: Data?
            
            switch format {
            case .pdf:
                if let pdf = PDFReportGenerator.shared.generateReport(config: config, dataStore: dataStore) {
                    data = pdf.dataRepresentation()
                }
            case .csv:
                data = XLSXReportGenerator.shared.generateReport(config: config, dataStore: dataStore)
            case .html:
                data = XLSXReportGenerator.shared.generateHTMLReport(config: config, dataStore: dataStore)
            }
            
            DispatchQueue.main.async {
                exportData = data
                isGenerating = false
                
                // Add to recent exports
                let export = RecentExport(
                    date: Date(),
                    template: selectedTemplate,
                    format: format,
                    fileName: generateFileName(for: format)
                )
                recentExports.insert(export, at: 0)
                showingExportSheet = true
            }
        }
    }
    
    private func generateFileName(for format: ExportFormat) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let templateStr = selectedTemplate.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        return "judge_chronos_\(templateStr)_\(dateStr).\(format.fileExtension)"
    }
}

// MARK: - Template Section
struct TemplateSection: View {
    @Binding var selectedTemplate: ReportTemplate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Template")
                .font(.headline)
            
            Picker("Template", selection: $selectedTemplate) {
                ForEach(ReportTemplate.allCases, id: \.self) { template in
                    Text(template.rawValue).tag(template)
                }
            }
            .pickerStyle(.segmented)
            
            Text(templateDescription(selectedTemplate))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func templateDescription(_ template: ReportTemplate) -> String {
        switch template {
        case .invoice:
            return "Professional invoice with line items, rates, and totals"
        case .timesheet:
            return "Detailed timesheet showing all time entries"
        case .detailedLog:
            return "Complete activity log with all metadata"
        case .projectSummary:
            return "Summary report grouped by project"
        case .productivityReport:
            return "Analytics and productivity insights"
        }
    }
}

// MARK: - Date Range Section
struct DateRangeSection: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date Range")
                .font(.headline)
            
            HStack(spacing: 16) {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
                DatePicker("End", selection: $endDate, displayedComponents: .date)
            }
            
            // Quick presets
            HStack(spacing: 8) {
                PresetButton(title: "Today") {
                    startDate = Calendar.current.startOfDay(for: Date())
                    endDate = Date()
                }
                PresetButton(title: "This Week") {
                    startDate = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
                    endDate = Date()
                }
                PresetButton(title: "This Month") {
                    let components = Calendar.current.dateComponents([.year, .month], from: Date())
                    startDate = Calendar.current.date(from: components) ?? Date()
                    endDate = Date()
                }
                PresetButton(title: "Last 7 Days") {
                    startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                    endDate = Date()
                }
                PresetButton(title: "Last 30 Days") {
                    startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                    endDate = Date()
                }
            }
        }
    }
}

struct PresetButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Project Selection Section
struct ProjectSelectionSection: View {
    let projects: [Project]
    @Binding var selectedIds: Set<UUID>
    @Binding var includeSubprojects: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.headline)
            
            if projects.isEmpty {
                Text("No projects created yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                // All projects toggle
                Toggle("All Projects", isOn: .init(
                    get: { selectedIds.isEmpty },
                    set: { isAll in
                        if isAll {
                            selectedIds.removeAll()
                        }
                    }
                ))
                
                // Individual project toggles
                if !selectedIds.isEmpty || true {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(projects) { project in
                                ProjectToggleChip(
                                    project: project,
                                    isSelected: selectedIds.contains(project.id)
                                ) {
                                    if selectedIds.contains(project.id) {
                                        selectedIds.remove(project.id)
                                    } else {
                                        selectedIds.insert(project.id)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 40)
                }
                
                if !selectedIds.isEmpty {
                    Toggle("Include subprojects", isOn: $includeSubprojects)
                        .font(.caption)
                }
            }
        }
    }
}

struct ProjectToggleChip: View {
    let project: Project
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: project.colorHex) ?? .gray)
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grouping Section
struct GroupingSection: View {
    @Binding var groupBy: GroupingOption
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group By")
                .font(.headline)
            
            Picker("Grouping", selection: $groupBy) {
                ForEach(GroupingOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Invoice Details Section
struct InvoiceDetailsSection: View {
    @Binding var companyName: String
    @Binding var clientName: String
    @Binding var hourlyRate: String
    @Binding var taxRate: String
    @Binding var notes: String
    @Binding var showBillableOnly: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invoice Details")
                .font(.headline)
            
            TextField("Your Company Name", text: $companyName)
                .textFieldStyle(.roundedBorder)
            
            TextField("Client Name", text: $clientName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                TextField("Hourly Rate", text: $hourlyRate)
                    .textFieldStyle(.roundedBorder)
                Text("$")
            }
            
            HStack {
                TextField("Tax Rate", text: $taxRate)
                    .textFieldStyle(.roundedBorder)
                Text("%")
            }
            
            Toggle("Billable projects only", isOn: $showBillableOnly)
            
            TextEditor(text: $notes)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.2))
                )
        }
    }
}

// MARK: - Preview Summary Section
struct PreviewSummarySection: View {
    let config: ReportConfiguration
    @ObservedObject var dataStore: LocalDataStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
            
            let sessions = getSessions()
            let totalHours = sessions.reduce(0) { $0 + $1.duration } / 3600
            
            HStack(spacing: 20) {
                StatBox(title: "Sessions", value: "\(sessions.count)")
                StatBox(title: "Total Hours", value: String(format: "%.1f", totalHours))
                StatBox(title: "Projects", value: "\(Set(sessions.compactMap { $0.projectId }).count)")
            }
        }
    }
    
    private func getSessions() -> [Session] {
        dataStore.sessions.filter {
            $0.startTime >= config.startDate && $0.startTime <= config.endDate
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Preview Sheet
struct PDFPreviewSheet: View {
    let pdf: PDFDocument
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            
            PDFKitView(document: pdf)
        }
        .frame(width: 800, height: 600)
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}

// MARK: - Export Sheet
struct ExportSheet: View {
    let data: Data
    let format: ReportBuilderView.ExportFormat
    let config: ReportConfiguration
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Report")
                .font(.title2)
            
            Text("Your report is ready to download")
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                
                Button("Save") {
                    saveFile()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
    
    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = generateFileName()
        
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? data.write(to: url)
            }
            dismiss()
        }
    }
    
    private func generateFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let templateStr = config.template.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        return "judge_chronos_\(templateStr)_\(dateStr).\(format.fileExtension)"
    }
}

// MARK: - Recent Export Model
struct RecentExport: Identifiable {
    let id = UUID()
    let date: Date
    let template: ReportTemplate
    let format: ReportBuilderView.ExportFormat
    let fileName: String
}

// MARK: - Preview
#Preview {
    ReportBuilderView()
        .environmentObject(LocalDataStore.shared)
        .frame(width: 700, height: 800)
}
