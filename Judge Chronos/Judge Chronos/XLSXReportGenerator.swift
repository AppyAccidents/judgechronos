import Foundation

// MARK: - XLSX Report Generator
// Note: This is a simplified implementation. For full XLSX support,
// you would integrate CoreXLSX or create proper XML structure.

@MainActor
final class XLSXReportGenerator {
    static let shared = XLSXReportGenerator()
    
    private init() {}
    
    // MARK: - Generate Report
    func generateReport(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> Data? {
        // For now, generate a CSV-like format that Excel can open
        // Full XLSX implementation would require CoreXLSX library
        return generateCSVReport(config: config, dataStore: dataStore)
    }
    
    // MARK: - CSV Export (Excel-compatible)
    private func generateCSVReport(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> Data? {
        var csv = "data:text/csv;charset=utf-8,"
        
        // Header
        csv += "Date,Project,Description,Start Time,End Time,Duration (hours),Billable\n"
        
        let sessions = getSessions(for: config, dataStore: dataStore)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        for session in sessions.sorted(by: { $0.startTime < $1.startTime }) {
            let date = dateFormatter.string(from: session.startTime)
            let project = escapeCSV(dataStore.projectName(for: session.projectId))
            let description = escapeCSV(session.lastWindowTitle ?? session.sourceApp)
            let startTime = dateFormatter.string(from: session.startTime)
            let endTime = dateFormatter.string(from: session.endTime)
            let hours = String(format: "%.2f", session.duration / 3600)
            let billable = (dataStore.projects.first { $0.id == session.projectId }?.isBillable ?? false) ? "Yes" : "No"
            
            csv += "\(date),\(project),\(description),\(startTime),\(endTime),\(hours),\(billable)\n"
        }
        
        // Summary sheet
        csv += "\n"
        csv += "SUMMARY\n"
        csv += "Project,Total Hours\n"
        
        let projectTotals = calculateProjectTotals(sessions: sessions, dataStore: dataStore)
        for (projectName, hours) in projectTotals {
            csv += "\(escapeCSV(projectName)),\(String(format: "%.2f", hours))\n"
        }
        
        return csv.data(using: .utf8)
    }
    
    // MARK: - Multi-Sheet XLSX Structure (Simplified)
    func generateMultiSheetXLSX(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> Data? {
        // This would generate actual XLSX binary format
        // For MVP, we'll create a structured CSV that opens in Excel
        
        var output = """
        Timesheet Report
        Generated: \(Date())
        Period: \(config.startDate) - \(config.endDate)
        
        === DETAILED LOG ===
        
        """
        
        let sessions = getSessions(for: config, dataStore: dataStore)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        // Group by date
        let groupedByDate = Dictionary(grouping: sessions) { session in
            Calendar.current.startOfDay(for: session.startTime)
        }
        
        for (date, daySessions) in groupedByDate.sorted(by: { $0.key < $1.key }) {
            output += "\n\(dateFormatter.string(from: date))\n"
            output += String(repeating: "-", count: 50) + "\n"
            
            for session in daySessions.sorted(by: { $0.startTime < $1.startTime }) {
                let project = dataStore.projectName(for: session.projectId)
                let duration = formatDuration(session.duration)
                let description = session.lastWindowTitle ?? session.sourceApp
                
                output += "  \(dateFormatter.string(from: session.startTime)) - \(duration) | \(project) | \(description)\n"
            }
            
            let dayTotal = daySessions.reduce(0) { $0 + $1.duration }
            output += "  Day Total: \(formatDuration(dayTotal))\n"
        }
        
        // Summary section
        output += "\n\n=== PROJECT SUMMARY ===\n\n"
        let projectTotals = calculateProjectTotals(sessions: sessions, dataStore: dataStore)
        for (project, hours) in projectTotals.sorted(by: { $0.1 > $1.1 }) {
            output += "\(project): \(String(format: "%.2f", hours)) hours\n"
        }
        
        let grandTotal = sessions.reduce(0) { $0 + $1.duration } / 3600
        output += "\nGrand Total: \(String(format: "%.2f", grandTotal)) hours\n"
        
        return output.data(using: .utf8)
    }
    
    // MARK: - HTML Table Export
    func generateHTMLReport(
        config: ReportConfiguration,
        dataStore: LocalDataStore
    ) -> Data? {
        let sessions = getSessions(for: config, dataStore: dataStore)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Judge Chronos Report</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; }
                h1 { color: #333; border-bottom: 2px solid #667eea; padding-bottom: 10px; }
                table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                th { background: #667eea; color: white; padding: 12px; text-align: left; }
                td { padding: 10px; border-bottom: 1px solid #ddd; }
                tr:hover { background: #f5f5f5; }
                .summary { background: #f8fafc; padding: 20px; border-radius: 8px; margin-top: 30px; }
                .total { font-weight: bold; font-size: 1.2em; }
            </style>
        </head>
        <body>
            <h1>Timesheet Report</h1>
            <p>Period: \(dateFormatter.string(from: config.startDate)) - \(dateFormatter.string(from: config.endDate))</p>
            
            <table>
                <thead>
                    <tr>
                        <th>Date</th>
                        <th>Project</th>
                        <th>Description</th>
                        <th>Start</th>
                        <th>End</th>
                        <th>Duration</th>
                    </tr>
                </thead>
                <tbody>
        """
        
        for session in sessions.sorted(by: { $0.startTime < $1.startTime }) {
            let project = escapeHTML(dataStore.projectName(for: session.projectId))
            let description = escapeHTML(session.lastWindowTitle ?? session.sourceApp)
            let endTime = dateFormatter.string(from: session.endTime)
            
            html += """
                    <tr>
                        <td>\(dateFormatter.string(from: session.startTime))</td>
                        <td>\(project)</td>
                        <td>\(description)</td>
                        <td>\(dateFormatter.string(from: session.startTime))</td>
                        <td>\(endTime)</td>
                        <td>\(formatDuration(session.duration))</td>
                    </tr>
            """
        }
        
        let totalHours = sessions.reduce(0) { $0 + $1.duration } / 3600
        
        html += """
                </tbody>
            </table>
            
            <div class="summary">
                <p class="total">Total Hours: \(String(format: "%.2f", totalHours))</p>
            </div>
            
            <footer style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 0.9em;">
                Generated by Judge Chronos on \(Date())
            </footer>
        </body>
        </html>
        """
        
        return html.data(using: .utf8)
    }
    
    // MARK: - Helper Methods
    private func getSessions(for config: ReportConfiguration, dataStore: LocalDataStore) -> [Session] {
        return dataStore.sessions.filter {
            $0.startTime >= config.startDate && $0.startTime <= config.endDate
        }
    }
    
    private func calculateProjectTotals(sessions: [Session], dataStore: LocalDataStore) -> [(String, Double)] {
        let grouped = Dictionary(grouping: sessions) { $0.projectId }
        return grouped.map { (projectId, sessions) in
            let name = dataStore.projectName(for: projectId)
            let hours = sessions.reduce(0) { $0 + $1.duration } / 3600
            return (name, hours)
        }.sorted { $0.1 > $1.1 }
    }
    
    private func escapeCSV(_ value: String) -> String {
        var escaped = value
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            escaped = escaped.replacingOccurrences(of: "\"", with: "\"\"")
            escaped = "\"\(escaped)\""
        }
        return escaped
    }
    
    private func escapeHTML(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }
}
