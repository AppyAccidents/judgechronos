import Foundation
import AppKit

// MARK: - Browser Extension Message
struct BrowserMessage: Codable {
    let browser: String      // "chrome", "safari", "firefox"
    let url: String
    let title: String
    let domain: String
    let timestamp: Date
    let tabId: String?       // Optional tab identifier
    let windowFocused: Bool  // Whether the browser window is active
}

// MARK: - Browser Session Tracker
struct BrowserSession: Identifiable, Codable {
    let id: UUID
    let browser: String
    let domain: String
    let url: String
    let title: String
    let startTime: Date
    var endTime: Date?
    var isActive: Bool
    
    var duration: TimeInterval {
        endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
    }
}

// MARK: - Browser Extension Host
@MainActor
final class BrowserExtensionHost: ObservableObject {
    static let shared = BrowserExtensionHost()
    
    @Published private(set) var activeSessions: [BrowserSession] = []
    @Published private(set) var isListening = false
    
    private var messagePort: CFMessagePort?
    private var timer: Timer?
    private let minSessionDuration: TimeInterval = 5 // Minimum 5 seconds to record
    
    // MARK: - URL Categorization
    private let productiveDomains: Set<String> = [
        "github.com", "gitlab.com", "bitbucket.org",
        "stackoverflow.com", "docs.microsoft.com", "developer.apple.com",
        "figma.com", "sketch.com", "linear.app", "jira.com", "asana.com",
        "notion.so", "confluence.atlassian.com",
        "slack.com", "discord.com", // Work communication
    ]
    
    private let distractingDomains: Set<String> = [
        "facebook.com", "twitter.com", "x.com", "instagram.com",
        "tiktok.com", "youtube.com", "reddit.com", "netflix.com",
        "twitch.tv", "9gag.com"
    ]
    
    private init() {}
    
    // MARK: - Lifecycle
    func startListening() {
        guard !isListening else { return }
        isListening = true
        
        // Start cleanup timer for stale sessions
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupStaleSessions()
            }
        }
        
        print("[BrowserExtensionHost] Started listening for browser messages")
    }
    
    func stopListening() {
        isListening = false
        timer?.invalidate()
        timer = nil
        
        // End all active sessions
        for index in activeSessions.indices where activeSessions[index].isActive {
            activeSessions[index].isActive = false
            activeSessions[index].endTime = Date()
        }
    }
    
    // MARK: - Message Handling
    func handleMessage(_ message: BrowserMessage) {
        guard isListening else { return }
        
        // Check if there's an existing active session for this domain
        if let existingIndex = activeSessions.firstIndex(where: {
            $0.isActive && $0.browser == message.browser && $0.domain == message.domain
        }) {
            // Update existing session
            var session = activeSessions[existingIndex]
            session.endTime = nil // Extend session
            activeSessions[existingIndex] = session
        } else {
            // Close any other active session from this browser
            closeActiveSession(for: message.browser)
            
            // Create new session
            let newSession = BrowserSession(
                id: UUID(),
                browser: message.browser,
                domain: message.domain,
                url: message.url,
                title: message.title,
                startTime: message.timestamp,
                endTime: nil,
                isActive: true
            )
            activeSessions.append(newSession)
        }
        
        // Notify observers
        objectWillChange.send()
    }
    
    func handleBrowserLostFocus(browser: String) {
        closeActiveSession(for: browser)
    }
    
    func handleTabClosed(browser: String, tabId: String) {
        // Find and close session for this specific tab
        if let index = activeSessions.firstIndex(where: {
            $0.isActive && $0.browser == browser
        }) {
            activeSessions[index].isActive = false
            activeSessions[index].endTime = Date()
        }
    }
    
    private func closeActiveSession(for browser: String) {
        if let index = activeSessions.firstIndex(where: {
            $0.isActive && $0.browser == browser
        }) {
            activeSessions[index].isActive = false
            activeSessions[index].endTime = Date()
        }
    }
    
    private func cleanupStaleSessions() {
        let now = Date()
        let staleThreshold: TimeInterval = 60 // 60 seconds without update = stale
        
        for index in activeSessions.indices where activeSessions[index].isActive {
            let lastUpdate = activeSessions[index].endTime ?? activeSessions[index].startTime
            if now.timeIntervalSince(lastUpdate) > staleThreshold {
                activeSessions[index].isActive = false
                activeSessions[index].endTime = lastUpdate
            }
        }
        
        // Remove old completed sessions (keep last 24 hours)
        let retentionThreshold = now.addingTimeInterval(-86400)
        activeSessions.removeAll { session in
            !session.isActive && (session.endTime ?? session.startTime) < retentionThreshold
        }
    }
    
    // MARK: - URL Analysis
    func categorizeDomain(_ domain: String) -> ProductivityRating? {
        let lowercased = domain.lowercased()
        if productiveDomains.contains(where: { lowercased.contains($0) }) {
            return .productive
        }
        if distractingDomains.contains(where: { lowercased.contains($0) }) {
            return .distracting
        }
        return nil
    }
    
    func suggestProject(for domain: String, title: String) -> String? {
        // Map common domains to project names
        let domainProjects: [String: String] = [
            "github.com": "Development",
            "gitlab.com": "Development",
            "stackoverflow.com": "Research",
            "figma.com": "Design",
            "linear.app": "Project Management",
            "jira.com": "Project Management",
            "notion.so": "Documentation",
            "slack.com": "Communication"
        ]
        
        for (key, project) in domainProjects {
            if domain.contains(key) {
                return project
            }
        }
        
        return nil
    }
    
    // MARK: - Session Export
    func exportSessions(from startDate: Date, to endDate: Date) -> [BrowserSession] {
        activeSessions.filter { session in
            let sessionEnd = session.endTime ?? Date()
            return session.startTime < endDate && sessionEnd > startDate
        }
    }
    
    func clearHistory() {
        activeSessions.removeAll()
    }
}

// MARK: - URL Parser
enum URLParser {
    static func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }
    
    static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme?.hasPrefix("http") ?? false
    }
    
    static func sanitizeTitle(_ title: String, maxLength: Int = 100) -> String {
        let sanitized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if sanitized.count > maxLength {
            let index = sanitized.index(sanitized.startIndex, offsetBy: maxLength)
            return String(sanitized[..<index]) + "..."
        }
        return sanitized
    }
}

// MARK: - HTTP Server for Extension Communication (Optional)
// For browsers that support native messaging via HTTP localhost
#if DEBUG
final class BrowserExtensionHTTPServer: ObservableObject {
    @Published var lastMessage: BrowserMessage?
    
    func start(port: Int = 8765) {
        // In production, use proper native messaging
        // This is a debug fallback for easier development
        print("[BrowserExtensionHTTPServer] Would start on port \(port)")
    }
    
    func stop() {
        print("[BrowserExtensionHTTPServer] Stopped")
    }
}
#endif
