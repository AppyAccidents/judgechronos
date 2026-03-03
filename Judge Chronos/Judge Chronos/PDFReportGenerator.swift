import PDFKit
import AppKit

// MARK: - Report Templates
enum ReportTemplate: String, CaseIterable {
    case invoice = "Invoice"
    case timesheet = "Timesheet"
    case detailedLog = "Detailed Log"
    case projectSummary = "Project Summary"
    case productivityReport = "Productivity Report"
}

// MARK: - Report Configuration
struct ReportConfiguration {
    var template: ReportTemplate
    var startDate: Date
    var endDate: Date
    var projectIds: [UUID]?
    var includeSubprojects: Bool
    var groupBy: GroupingOption
    var companyName: String
    var companyLogo: NSImage?
    var clientName: String?
    var notes: String
    var hourlyRate: Double?
    var taxRate: Double?
    var showBillableOnly: Bool
}

enum GroupingOption: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case project = "Project"
    case task = "Task"
}

// MARK: - PDF Report Generator
@MainActor
final class PDFReportGenerator {
    static let shared = PDFReportGenerator()
    
    private init() {}
    
    // MARK: - Generate Report
    func generateReport(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        switch config.template {
        case .invoice:
            return generateInvoice(config: config, dataStore: dataStore)
        case .timesheet:
            return generateTimesheet(config: config, dataStore: dataStore)
        case .detailedLog:
            return generateDetailedLog(config: config, dataStore: dataStore)
        case .projectSummary:
            return generateProjectSummary(config: config, dataStore: dataStore)
        case .productivityReport:
            return generateProductivityReport(config: config, dataStore: dataStore)
        }
    }
    
    // MARK: - Invoice Template
    private func generateInvoice(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        let pdfDocument = PDFDocument()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        
        guard let page = PDFPage(image: NSImage(size: pageRect.size)) else { return nil }
        pdfDocument.insert(page, at: 0)
        
        // Get sessions for the date range
        let sessions = getSessions(for: config, dataStore: dataStore)
        
        // Start drawing
        var yPosition = pageRect.height - 50
        
        // Header
        if let logo = config.companyLogo {
            drawImage(logo, at: CGRect(x: 50, y: yPosition - 60, width: 100, height: 60), on: page)
        }
        
        yPosition -= 20
        drawText("INVOICE", at: CGPoint(x: pageRect.width - 150, y: yPosition), 
                font: .boldSystemFont(ofSize: 28), on: page)
        
        yPosition -= 40
        drawText(config.companyName, at: CGPoint(x: 50, y: yPosition), 
                font: .boldSystemFont(ofSize: 14), on: page)
        
        yPosition -= 20
        drawText("Bill To:", at: CGPoint(x: 50, y: yPosition), 
                font: .boldSystemFont(ofSize: 12), on: page)
        yPosition -= 15
        drawText(config.clientName ?? "Client", at: CGPoint(x: 50, y: yPosition), 
                font: .systemFont(ofSize: 11), on: page)
        
        // Invoice details
        yPosition -= 40
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        drawText("Invoice Date: \(dateFormatter.string(from: Date()))", 
                at: CGPoint(x: pageRect.width - 200, y: yPosition), 
                font: .systemFont(ofSize: 10), on: page)
        yPosition -= 15
        drawText("Period: \(dateFormatter.string(from: config.startDate)) - \(dateFormatter.string(from: config.endDate))", 
                at: CGPoint(x: pageRect.width - 200, y: yPosition), 
                font: .systemFont(ofSize: 10), on: page)
        
        // Table header
        yPosition -= 60
        drawTableHeader(at: &yPosition, page: page, pageWidth: pageRect.width)
        
        // Line items
        let groupedSessions = groupSessions(sessions, by: config.groupBy)
        var totalHours: TimeInterval = 0
        var totalAmount: Double = 0
        
        for (groupName, groupSessions) in groupedSessions {
            let hours = groupSessions.reduce(0) { $0 + $1.duration } / 3600
            let rate = config.hourlyRate ?? 0
            let amount = hours * rate
            totalHours += hours
            totalAmount += amount
            
            if yPosition < 100 {
                // Add new page
                if let newPage = PDFPage(image: NSImage(size: pageRect.size)) {
                    pdfDocument.insert(newPage, at: pdfDocument.pageCount)
                    yPosition = pageRect.height - 50
                }
            }
            
            drawLineItem(
                description: groupName,
                hours: hours,
                rate: rate,
                amount: amount,
                at: &yPosition,
                page: page,
                pageWidth: pageRect.width
            )
        }
        
        // Totals
        yPosition -= 30
        drawSeparator(at: yPosition, pageWidth: pageRect.width, on: page)
        yPosition -= 20
        
        let subtotal = totalAmount
        let tax = subtotal * (config.taxRate ?? 0) / 100
        let grandTotal = subtotal + tax
        
        drawText("Subtotal:", at: CGPoint(x: pageRect.width - 250, y: yPosition), 
                font: .boldSystemFont(ofSize: 11), on: page)
        drawText(String(format: "$%.2f", subtotal), at: CGPoint(x: pageRect.width - 100, y: yPosition), 
                font: .systemFont(ofSize: 11), on: page)
        
        yPosition -= 15
        drawText("Tax (\(config.taxRate ?? 0)%):", at: CGPoint(x: pageRect.width - 250, y: yPosition), 
                font: .boldSystemFont(ofSize: 11), on: page)
        drawText(String(format: "$%.2f", tax), at: CGPoint(x: pageRect.width - 100, y: yPosition), 
                font: .systemFont(ofSize: 11), on: page)
        
        yPosition -= 20
        drawText("Total:", at: CGPoint(x: pageRect.width - 250, y: yPosition), 
                font: .boldSystemFont(ofSize: 14), on: page)
        drawText(String(format: "$%.2f", grandTotal), at: CGPoint(x: pageRect.width - 100, y: yPosition), 
                font: .boldSystemFont(ofSize: 14), on: page)
        
        // Notes
        if !config.notes.isEmpty {
            yPosition -= 50
            drawText("Notes:", at: CGPoint(x: 50, y: yPosition), 
                    font: .boldSystemFont(ofSize: 11), on: page)
            yPosition -= 15
            drawText(config.notes, at: CGPoint(x: 50, y: yPosition), 
                    font: .systemFont(ofSize: 10), on: page)
        }
        
        return pdfDocument
    }
    
    // MARK: - Timesheet Template
    private func generateTimesheet(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        let pdfDocument = PDFDocument()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        
        guard let page = PDFPage(image: NSImage(size: pageRect.size)) else { return nil }
        pdfDocument.insert(page, at: 0)
        
        let sessions = getSessions(for: config, dataStore: dataStore)
        var yPosition = pageRect.height - 50
        
        // Title
        drawText("TIMESHEET", at: CGPoint(x: 50, y: yPosition), 
                font: .boldSystemFont(ofSize: 24), on: page)
        
        yPosition -= 40
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        drawText("Period: \(dateFormatter.string(from: config.startDate)) - \(dateFormatter.string(from: config.endDate))", 
                at: CGPoint(x: 50, y: yPosition), font: .systemFont(ofSize: 12), on: page)
        
        // Table
        yPosition -= 50
        let tableHeaders = ["Date", "Project", "Description", "Start", "End", "Duration"]
        drawTimesheetHeaders(headers: tableHeaders, at: &yPosition, page: page, pageWidth: pageRect.width)
        
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateStyle = .short
        dateTimeFormatter.timeStyle = .short
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        for session in sessions.sorted(by: { $0.startTime < $1.startTime }) {
            if yPosition < 100 {
                if let newPage = PDFPage(image: NSImage(size: pageRect.size)) {
                    pdfDocument.insert(newPage, at: pdfDocument.pageCount)
                    yPosition = pageRect.height - 50
                    drawTimesheetHeaders(headers: tableHeaders, at: &yPosition, page: newPage, pageWidth: pageRect.width)
                }
            }
            
            let projectName = dataStore.projectName(for: session.projectId)
            let description = session.lastWindowTitle ?? session.sourceApp
            
            drawTimesheetRow(
                date: dateTimeFormatter.string(from: session.startTime),
                project: projectName,
                description: description,
                start: timeFormatter.string(from: session.startTime),
                end: timeFormatter.string(from: session.endTime),
                duration: formatDuration(session.duration),
                at: &yPosition,
                page: page,
                pageWidth: pageRect.width
            )
        }
        
        return pdfDocument
    }
    
    // MARK: - Detailed Log Template
    private func generateDetailedLog(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        let pdfDocument = PDFDocument()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        
        guard let page = PDFPage(image: NSImage(size: pageRect.size)) else { return nil }
        pdfDocument.insert(page, at: 0)
        
        let sessions = getSessions(for: config, dataStore: dataStore)
        var yPosition = pageRect.height - 50
        
        drawText("DETAILED ACTIVITY LOG", at: CGPoint(x: 50, y: yPosition), 
                font: .boldSystemFont(ofSize: 24), on: page)
        
        // Detailed list with all metadata
        // Implementation similar to timesheet but with more detail
        
        return pdfDocument
    }
    
    // MARK: - Project Summary Template
    private func generateProjectSummary(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        // Implementation for project summary report
        return nil
    }
    
    // MARK: - Productivity Report Template
    private func generateProductivityReport(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        // Implementation for productivity analytics report
        return nil
    }
    
    // MARK: - Helper Methods
    private func getSessions(for config: ReportConfiguration, dataStore: LocalDataStore) -> [Session] {
        let baseSessions = dataStore.sessions.filter {
            $0.startTime >= config.startDate && $0.endTime <= config.endDate
        }
        
        if let projectIds = config.projectIds, !projectIds.isEmpty {
            if config.includeSubprojects {
                var allProjectIds = Set(projectIds)
                for projectId in projectIds {
                    let descendants = dataStore.descendantProjectIds(of: projectId)
                    allProjectIds.formUnion(descendants)
                }
                return baseSessions.filter { allProjectIds.contains($0.projectId ?? UUID()) }
            } else {
                return baseSessions.filter { projectIds.contains($0.projectId ?? UUID()) }
            }
        }
        
        if config.showBillableOnly {
            let billableProjectIds = Set(dataStore.projects.filter { $0.isBillable }.map { $0.id })
            return baseSessions.filter { billableProjectIds.contains($0.projectId ?? UUID()) }
        }
        
        return baseSessions
    }
    
    private func groupSessions(_ sessions: [Session], by option: GroupingOption) -> [(String, [Session])] {
        switch option {
        case .day:
            let grouped = Dictionary(grouping: sessions) { session in
                Calendar.current.startOfDay(for: session.startTime)
            }
            return grouped.map { (key, value) in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return (formatter.string(from: key), value)
            }.sorted { $0.0 < $1.0 }
            
        case .week:
            let grouped = Dictionary(grouping: sessions) { session in
                Calendar.current.component(.weekOfYear, from: session.startTime)
            }
            return grouped.map { (key, value) in ("Week \(key)", value) }
                .sorted { $0.0 < $1.0 }
            
        case .project:
            return Dictionary(grouping: sessions) { $0.projectId }
                .map { (key, value) in (key?.uuidString ?? "Uncategorized", value) }
            
        case .task:
            return Dictionary(grouping: sessions) { $0.lastWindowTitle ?? "Unknown" }
                .map { ($0.key, $0.value) }
        }
    }
    
    // MARK: - Drawing Helpers
    private func drawText(_ text: String, at point: CGPoint, font: NSFont, on page: PDFPage) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        attributedString.draw(at: point)
    }
    
    private func drawImage(_ image: NSImage, at rect: CGRect, on page: PDFPage) {
        image.draw(in: rect)
    }
    
    private func drawTableHeader(at yPosition: inout CGFloat, page: PDFPage, pageWidth: CGFloat) {
        let columns = ["Description", "Hours", "Rate", "Amount"]
        let xPositions: [CGFloat] = [50, 300, 380, 460]
        
        for (index, column) in columns.enumerated() {
            drawText(column, at: CGPoint(x: xPositions[index], y: yPosition), 
                    font: .boldSystemFont(ofSize: 11), on: page)
        }
        
        yPosition -= 5
        drawSeparator(at: yPosition, pageWidth: pageWidth, on: page)
        yPosition -= 15
    }
    
    private func drawLineItem(
        description: String,
        hours: TimeInterval,
        rate: Double,
        amount: Double,
        at yPosition: inout CGFloat,
        page: PDFPage,
        pageWidth: CGFloat
    ) {
        drawText(description, at: CGPoint(x: 50, y: yPosition), 
                font: .systemFont(ofSize: 10), on: page)
        drawText(String(format: "%.2f", hours), at: CGPoint(x: 300, y: yPosition), 
                font: .systemFont(ofSize: 10), on: page)
        drawText(String(format: "$%.2f", rate), at: CGPoint(x: 380, y: yPosition), 
                font: .systemFont(ofSize: 10), on: page)
        drawText(String(format: "$%.2f", amount), at: CGPoint(x: 460, y: yPosition), 
                font: .systemFont(ofSize: 10), on: page)
        
        yPosition -= 20
    }
    
    private func drawTimesheetHeaders(headers: [String], at yPosition: inout CGFloat, page: PDFPage, pageWidth: CGFloat) {
        let xPositions: [CGFloat] = [50, 110, 220, 380, 440, 500]
        
        for (index, header) in headers.enumerated() {
            drawText(header, at: CGPoint(x: xPositions[index], y: yPosition), 
                    font: .boldSystemFont(ofSize: 10), on: page)
        }
        
        yPosition -= 5
        drawSeparator(at: yPosition, pageWidth: pageWidth, on: page)
        yPosition -= 15
    }
    
    private func drawTimesheetRow(
        date: String,
        project: String,
        description: String,
        start: String,
        end: String,
        duration: String,
        at yPosition: inout CGFloat,
        page: PDFPage,
        pageWidth: CGFloat
    ) {
        let xPositions: [CGFloat] = [50, 110, 220, 380, 440, 500]
        let values = [date, project, description, start, end, duration]
        
        for (index, value) in values.enumerated() {
            let truncated = String(value.prefix(25))
            drawText(truncated, at: CGPoint(x: xPositions[index], y: yPosition), 
                    font: .systemFont(ofSize: 9), on: page)
        }
        
        yPosition -= 15
    }
    
    private func drawSeparator(at y: CGFloat, pageWidth: CGFloat, on page: PDFPage) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 50, y: y))
        path.line(to: CGPoint(x: pageWidth - 50, y: y))
        path.lineWidth = 0.5
        NSColor.gray.setStroke()
        path.stroke()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
