import Foundation

struct ContextEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let bundleId: String
    let appName: String
    let windowTitle: String?
    let documentPath: String?
    
    // Privacy: sanitize before saving
    static func sanitize(_ text: String) -> String {
        // Simple heuristic: remove potential email addresses
        // This is a basic implementation; robust PII stripping is complex
        let emailRegex = try? NSRegularExpression(pattern: "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}")
        let range = NSRange(location: 0, length: text.utf16.count)
        return emailRegex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[REDACTED_EMAIL]") ?? text
    }
}
