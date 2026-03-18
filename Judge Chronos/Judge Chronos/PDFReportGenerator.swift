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
        
        let currencySymbol = dataStore.preferences.currency
        drawText("Subtotal:", at: CGPoint(x: pageRect.width - 250, y: yPosition),
                font: .boldSystemFont(ofSize: 11), on: page)
        drawText(String(format: "%@ %.2f", currencySymbol, subtotal), at: CGPoint(x: pageRect.width - 100, y: yPosition),
                font: .systemFont(ofSize: 11), on: page)

        yPosition -= 15
        drawText("Tax (\(config.taxRate ?? 0)%):", at: CGPoint(x: pageRect.width - 250, y: yPosition),
                font: .boldSystemFont(ofSize: 11), on: page)
        drawText(String(format: "%@ %.2f", currencySymbol, tax), at: CGPoint(x: pageRect.width - 100, y: yPosition),
                font: .systemFont(ofSize: 11), on: page)

        yPosition -= 20
        drawText("Total:", at: CGPoint(x: pageRect.width - 250, y: yPosition),
                font: .boldSystemFont(ofSize: 14), on: page)
        drawText(String(format: "%@ %.2f", currencySymbol, grandTotal), at: CGPoint(x: pageRect.width - 100, y: yPosition),
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

        guard var currentPage = PDFPage(image: NSImage(size: pageRect.size)) else { return nil }
        pdfDocument.insert(currentPage, at: 0)

        let sessions = getSessions(for: config, dataStore: dataStore).sorted { $0.startTime < $1.startTime }
        var yPosition = pageRect.height - 50

        drawText("DETAILED ACTIVITY LOG", at: CGPoint(x: 50, y: yPosition),
                font: .boldSystemFont(ofSize: 24), on: currentPage)

        yPosition -= 30
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        drawText("Period: \(dateFormatter.string(from: config.startDate)) - \(dateFormatter.string(from: config.endDate))",
                at: CGPoint(x: 50, y: yPosition), font: .systemFont(ofSize: 12), on: currentPage)
        drawText("Total: \(sessions.count) sessions, \(formatDuration(sessions.reduce(0) { $0 + $1.duration }))",
                at: CGPoint(x: 350, y: yPosition), font: .systemFont(ofSize: 10), on: currentPage)

        yPosition -= 40

        // Headers
        let headers = ["Date", "Time", "App", "Window Title", "Project", "Category", "Duration"]
        let xPos: [CGFloat] = [50, 100, 180, 280, 380, 440, 520]

        func drawHeaders(on page: PDFPage, at y: inout CGFloat) {
            for (i, header) in headers.enumerated() {
                drawText(header, at: CGPoint(x: xPos[i], y: y), font: .boldSystemFont(ofSize: 9), on: page)
            }
            y -= 5
            drawSeparator(at: y, pageWidth: pageRect.width, on: page)
            y -= 12
        }

        drawHeaders(on: currentPage, at: &yPosition)

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateFormat = "MM/dd"

        for session in sessions {
            if yPosition < 80 {
                guard let newPage = PDFPage(image: NSImage(size: pageRect.size)) else { continue }
                pdfDocument.insert(newPage, at: pdfDocument.pageCount)
                currentPage = newPage
                yPosition = pageRect.height - 50
                drawHeaders(on: currentPage, at: &yPosition)
            }

            let projectName = dataStore.projectName(for: session.projectId)
            let categoryName = dataStore.categoryName(for: session.categoryId)
            let windowTitle = session.lastWindowTitle ?? ""

            let values = [
                shortDateFormatter.string(from: session.startTime),
                "\(timeFormatter.string(from: session.startTime))-\(timeFormatter.string(from: session.endTime))",
                String(session.sourceApp.prefix(15)),
                String(windowTitle.prefix(15)),
                String(projectName.prefix(10)),
                String(categoryName.prefix(10)),
                formatDuration(session.duration)
            ]

            for (i, value) in values.enumerated() {
                drawText(value, at: CGPoint(x: xPos[i], y: yPosition), font: .systemFont(ofSize: 8), on: currentPage)
            }

            // Note on second line if present
            if let note = session.note, !note.isEmpty {
                yPosition -= 10
                drawText("  Note: \(String(note.prefix(80)))", at: CGPoint(x: 50, y: yPosition),
                        font: .systemFont(ofSize: 7), on: currentPage)
            }

            yPosition -= 14
        }

        return pdfDocument
    }

    // MARK: - Project Summary Template
    private func generateProjectSummary(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        let pdfDocument = PDFDocument()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard var currentPage = PDFPage(image: NSImage(size: pageRect.size)) else { return nil }
        pdfDocument.insert(currentPage, at: 0)

        let sessions = getSessions(for: config, dataStore: dataStore)
        var yPosition = pageRect.height - 50

        drawText("PROJECT SUMMARY", at: CGPoint(x: 50, y: yPosition),
                font: .boldSystemFont(ofSize: 24), on: currentPage)

        yPosition -= 30
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        drawText("Period: \(dateFormatter.string(from: config.startDate)) - \(dateFormatter.string(from: config.endDate))",
                at: CGPoint(x: 50, y: yPosition), font: .systemFont(ofSize: 12), on: currentPage)

        yPosition -= 50

        // Group by project
        let grouped = Dictionary(grouping: sessions) { $0.projectId }
        let sortedGroups = grouped.sorted { a, b in
            let aTime = a.value.reduce(0) { $0 + $1.duration }
            let bTime = b.value.reduce(0) { $0 + $1.duration }
            return aTime > bTime
        }

        for (projectId, projectSessions) in sortedGroups {
            if yPosition < 120 {
                guard let newPage = PDFPage(image: NSImage(size: pageRect.size)) else { continue }
                pdfDocument.insert(newPage, at: pdfDocument.pageCount)
                currentPage = newPage
                yPosition = pageRect.height - 50
            }

            let projectName = dataStore.projectName(for: projectId)
            let totalTime = projectSessions.reduce(0) { $0 + $1.duration }
            let totalHours = totalTime / 3600
            let billableSessions = projectSessions.filter { s in
                guard let pid = s.projectId else { return false }
                return dataStore.projects.first(where: { $0.id == pid })?.isBillable ?? false
            }
            let billableHours = billableSessions.reduce(0) { $0 + $1.duration } / 3600

            // Client info
            if let pid = projectId,
               let project = dataStore.projects.first(where: { $0.id == pid }),
               let clientId = project.clientId {
                let clientName = dataStore.clientName(for: clientId)
                drawText("Client: \(clientName)", at: CGPoint(x: 50, y: yPosition),
                        font: .systemFont(ofSize: 9), on: currentPage)
                yPosition -= 14
            }

            drawText(projectName, at: CGPoint(x: 50, y: yPosition),
                    font: .boldSystemFont(ofSize: 13), on: currentPage)
            yPosition -= 18

            drawText("Total: \(formatDuration(totalTime)) (\(String(format: "%.1f", totalHours))h)",
                    at: CGPoint(x: 70, y: yPosition), font: .systemFont(ofSize: 10), on: currentPage)
            drawText("Billable: \(String(format: "%.1f", billableHours))h",
                    at: CGPoint(x: 280, y: yPosition), font: .systemFont(ofSize: 10), on: currentPage)

            let rate = config.hourlyRate ?? dataStore.projects.first(where: { $0.id == projectId })?.hourlyRate ?? 0
            if rate > 0 {
                let earned = billableHours * rate
                drawText("Earned: \(String(format: "%.2f", earned))",
                        at: CGPoint(x: 420, y: yPosition), font: .systemFont(ofSize: 10), on: currentPage)
            }
            yPosition -= 16

            // Budget usage bar
            if let pid = projectId {
                let pct = BudgetService.shared.budgetPercentage(for: pid, dataStore: dataStore)
                if let timePct = pct.time {
                    drawText("Budget: \(Int(timePct * 100))%", at: CGPoint(x: 70, y: yPosition),
                            font: .systemFont(ofSize: 9), on: currentPage)
                    yPosition -= 14
                }
            }

            // Activity breakdown
            let activityGrouped = Dictionary(grouping: projectSessions) { $0.activityId }
            for (activityId, actSessions) in activityGrouped {
                let actName = dataStore.activityName(for: activityId)
                let actTime = actSessions.reduce(0) { $0 + $1.duration }
                drawText("  \(actName): \(formatDuration(actTime))", at: CGPoint(x: 90, y: yPosition),
                        font: .systemFont(ofSize: 9), on: currentPage)
                yPosition -= 12
            }

            yPosition -= 10
            drawSeparator(at: yPosition, pageWidth: pageRect.width, on: currentPage)
            yPosition -= 20
        }

        return pdfDocument
    }

    // MARK: - Productivity Report Template
    private func generateProductivityReport(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> PDFDocument? {
        let pdfDocument = PDFDocument()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let page = PDFPage(image: NSImage(size: pageRect.size)) else { return nil }
        pdfDocument.insert(page, at: 0)

        let sessions = getSessions(for: config, dataStore: dataStore)
        var yPosition = pageRect.height - 50

        drawText("PRODUCTIVITY REPORT", at: CGPoint(x: 50, y: yPosition),
                font: .boldSystemFont(ofSize: 24), on: page)

        yPosition -= 30
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        drawText("Period: \(dateFormatter.string(from: config.startDate)) - \(dateFormatter.string(from: config.endDate))",
                at: CGPoint(x: 50, y: yPosition), font: .systemFont(ofSize: 12), on: page)

        yPosition -= 50

        // Daily productivity scores
        drawText("Daily Productivity Scores", at: CGPoint(x: 50, y: yPosition),
                font: .boldSystemFont(ofSize: 14), on: page)
        yPosition -= 20

        let calendar = Calendar.current
        let engine = ProductivityEngine.shared
        var currentDate = config.startDate
        while currentDate <= config.endDate {
            if yPosition < 80 { break }
            let score = engine.calculateDailyScore(for: currentDate, dataStore: dataStore)
            let dayStr = dateFormatter.string(from: currentDate)
            drawText(dayStr, at: CGPoint(x: 70, y: yPosition), font: .systemFont(ofSize: 10), on: page)
            drawText(String(format: "%.2f", score.overallScore), at: CGPoint(x: 200, y: yPosition),
                    font: .systemFont(ofSize: 10), on: page)
            drawText("Prod: \(String(format: "%.1f", score.productiveHours))h  Dist: \(String(format: "%.1f", score.distractingHours))h",
                    at: CGPoint(x: 260, y: yPosition), font: .systemFont(ofSize: 9), on: page)
            yPosition -= 14
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(86400)
        }

        yPosition -= 20

        // Top apps
        drawText("Top Productive Apps", at: CGPoint(x: 50, y: yPosition),
                font: .boldSystemFont(ofSize: 14), on: page)
        yPosition -= 18

        let appGroups = Dictionary(grouping: sessions.filter { !$0.isIdle }) { $0.sourceApp }
        let sortedApps = appGroups
            .map { (name: $0.key, time: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.time > $1.time }

        let productiveApps = sortedApps.filter { app in
            let project = sessions.first(where: { $0.sourceApp == app.name })?.projectId
            let rating = project.flatMap { pid in dataStore.projects.first(where: { $0.id == pid }) }?.productivityRating
            return (rating?.rawValue ?? 0) >= 0
        }

        for app in productiveApps.prefix(5) {
            drawText("\(app.name): \(formatDuration(app.time))", at: CGPoint(x: 70, y: yPosition),
                    font: .systemFont(ofSize: 10), on: page)
            yPosition -= 14
        }

        yPosition -= 10
        drawText("Top Distracting Apps", at: CGPoint(x: 50, y: yPosition),
                font: .boldSystemFont(ofSize: 14), on: page)
        yPosition -= 18

        let distractingApps = sortedApps.filter { app in
            let project = sessions.first(where: { $0.sourceApp == app.name })?.projectId
            let rating = project.flatMap { pid in dataStore.projects.first(where: { $0.id == pid }) }?.productivityRating
            return (rating?.rawValue ?? 0) < 0
        }

        for app in distractingApps.prefix(5) {
            drawText("\(app.name): \(formatDuration(app.time))", at: CGPoint(x: 70, y: yPosition),
                    font: .systemFont(ofSize: 10), on: page)
            yPosition -= 14
        }

        yPosition -= 20

        // Streak info
        drawText("Streaks", at: CGPoint(x: 50, y: yPosition),
                font: .boldSystemFont(ofSize: 14), on: page)
        yPosition -= 18
        drawText("Current streak: \(engine.currentStreak) days", at: CGPoint(x: 70, y: yPosition),
                font: .systemFont(ofSize: 10), on: page)
        yPosition -= 14
        drawText("Best streak: \(engine.bestStreak) days", at: CGPoint(x: 70, y: yPosition),
                font: .systemFont(ofSize: 10), on: page)

        return pdfDocument
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
