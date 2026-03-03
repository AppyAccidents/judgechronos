import Foundation
import AppKit
import ApplicationServices

// MARK: - Detected Call Model
struct DetectedCall: Identifiable, Equatable {
    let id = UUID()
    let app: CallApp
    let startTime: Date
    var endTime: Date?
    let title: String?
    let participants: [String]?
    var isActive: Bool = true
    
    var duration: TimeInterval {
        endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
    
    static func == (lhs: DetectedCall, rhs: DetectedCall) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Call App Types
enum CallApp: String, CaseIterable {
    case zoom = "zoom"
    case teams = "teams"
    case meet = "meet"
    case slack = "slack"
    case webex = "webex"
    case facetime = "facetime"
    
    var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .meet: return "Google Meet"
        case .slack: return "Slack"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        }
    }
    
    var icon: String {
        switch self {
        case .zoom: return "video.fill"
        case .teams: return "person.2.fill"
        case .meet: return "video.circle.fill"
        case .slack: return "bubble.left.fill"
        case .webex: return "video.badge.checkmark"
        case .facetime: return "video.fill"
        }
    }
    
    var bundleIdentifier: String {
        switch self {
        case .zoom: return "us.zoom.xos"
        case .teams: return "com.microsoft.teams"
        case .meet: return "com.google.Chrome" // Meet runs in browser
        case .slack: return "com.tinyspeck.slackmacgap"
        case .webex: return "com.cisco.webexmeetingsapp"
        case .facetime: return "com.apple.FaceTime"
        }
    }
    
    // Window title patterns that indicate an active call
    var callWindowPatterns: [String] {
        switch self {
        case .zoom:
            return ["zoom meeting", "zoom webinar"]
        case .teams:
            return ["microsoft teams call", "teams call"]
        case .meet:
            return ["meet.google.com", "google meet"]
        case .slack:
            return ["slack huddle", "slack call"]
        case .webex:
            return ["webex meeting", "webex call"]
        case .facetime:
            return ["facetime"]
        }
    }
}

// MARK: - Call Detector
@MainActor
final class CallDetector: ObservableObject {
    static let shared = CallDetector()
    
    @Published private(set) var activeCalls: [DetectedCall] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastDetectedCall: DetectedCall?
    
    // Callback for when a call ends
    var onCallEnded: ((DetectedCall) -> Void)?
    
    private var timer: Timer?
    private let checkInterval: TimeInterval = 2.0 // Check every 2 seconds
    private var previousCallStates: [CallApp: Bool] = [:]
    
    private init() {}
    
    // MARK: - Lifecycle
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Initial check
        checkForActiveCalls()
        
        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForActiveCalls()
            }
        }
        
        print("[CallDetector] Started monitoring for video calls")
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        activeCalls.removeAll()
        print("[CallDetector] Stopped monitoring")
    }
    
    // MARK: - Call Detection
    private func checkForActiveCalls() {
        for app in CallApp.allCases {
            let isInCall = detectCall(for: app)
            let wasInCall = previousCallStates[app] ?? false
            
            if isInCall && !wasInCall {
                // Call started
                let call = DetectedCall(
                    app: app,
                    startTime: Date(),
                    endTime: nil,
                    title: detectCallTitle(for: app),
                    participants: nil,
                    isActive: true
                )
                activeCalls.append(call)
                print("[CallDetector] Call started: \(app.displayName)")
                
            } else if !isInCall && wasInCall {
                // Call ended
                if let index = activeCalls.firstIndex(where: { $0.app == app && $0.isActive }) {
                    activeCalls[index].isActive = false
                    activeCalls[index].endTime = Date()
                    lastDetectedCall = activeCalls[index]
                    
                    print("[CallDetector] Call ended: \(app.displayName), duration: \(activeCalls[index].formattedDuration)")
                    
                    // Notify delegate
                    onCallEnded?(activeCalls[index])
                    
                    // Remove after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                        self?.activeCalls.removeAll { $0.id == self?.activeCalls[index].id }
                    }
                }
            }
            
            previousCallStates[app] = isInCall
        }
    }
    
    // MARK: - Detection Methods
    private func detectCall(for app: CallApp) -> Bool {
        switch app {
        case .zoom:
            return detectZoomCall()
        case .teams:
            return detectTeamsCall()
        case .meet:
            return detectMeetCall()
        case .slack:
            return detectSlackCall()
        case .webex:
            return detectWebexCall()
        case .facetime:
            return detectFaceTimeCall()
        }
    }
    
    private func detectZoomCall() -> Bool {
        // Check for Zoom process
        guard isAppRunning(bundleId: CallApp.zoom.bundleIdentifier) else { return false }
        
        // Check window titles
        return checkWindowTitles(for: CallApp.zoom)
    }
    
    private func detectTeamsCall() -> Bool {
        guard isAppRunning(bundleId: CallApp.teams.bundleIdentifier) else { return false }
        return checkWindowTitles(for: CallApp.teams)
    }
    
    private func detectMeetCall() -> Bool {
        // Google Meet runs in browser - check browser windows
        return checkBrowserForMeet()
    }
    
    private func detectSlackCall() -> Bool {
        guard isAppRunning(bundleId: CallApp.slack.bundleIdentifier) else { return false }
        return checkWindowTitles(for: CallApp.slack)
    }
    
    private func detectWebexCall() -> Bool {
        guard isAppRunning(bundleId: CallApp.webex.bundleIdentifier) else { return false }
        return checkWindowTitles(for: CallApp.webex)
    }
    
    private func detectFaceTimeCall() -> Bool {
        guard isAppRunning(bundleId: CallApp.facetime.bundleIdentifier) else { return false }
        return checkWindowTitles(for: CallApp.facetime)
    }
    
    // MARK: - Helper Methods
    private func isAppRunning(bundleId: String) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { $0.bundleIdentifier == bundleId }
    }
    
    private func checkWindowTitles(for app: CallApp) -> Bool {
        // Get all windows
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let windowName = window[kCGWindowName as String] as? String else {
                continue
            }
            
            // Check if window belongs to the app
            let appNameLower = ownerName.lowercased()
            let windowNameLower = windowName.lowercased()
            
            // Match app name
            let matchesApp: Bool
            switch app {
            case .zoom:
                matchesApp = appNameLower.contains("zoom")
            case .teams:
                matchesApp = appNameLower.contains("teams")
            case .slack:
                matchesApp = appNameLower.contains("slack")
            case .webex:
                matchesApp = appNameLower.contains("webex")
            case .facetime:
                matchesApp = appNameLower.contains("facetime")
            case .meet:
                matchesApp = false // Handled separately
            }
            
            if matchesApp {
                // Check window title patterns
                for pattern in app.callWindowPatterns {
                    if windowNameLower.contains(pattern) {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    private func checkBrowserForMeet() -> Bool {
        // Check browser extensions via BrowserExtensionHost
        // For now, rely on window title check
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        for window in windowList {
            guard let windowName = window[kCGWindowName as String] as? String else { continue }
            let windowNameLower = windowName.lowercased()
            
            if windowNameLower.contains("meet.google.com") ||
               windowNameLower.contains("google meet") {
                return true
            }
        }
        
        return false
    }
    
    private func detectCallTitle(for app: CallApp) -> String? {
        // Try to extract meeting title from window
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for window in windowList {
            guard let ownerName = window[kCGWindowOwnerName as String] as? String,
                  let windowName = window[kCGWindowName as String] as? String else {
                continue
            }
            
            let appNameLower = ownerName.lowercased()
            let windowNameLower = windowName.lowercased()
            
            switch app {
            case .zoom:
                if appNameLower.contains("zoom") && !windowName.isEmpty {
                    // Extract meeting name from "Zoom Meeting - Meeting Name"
                    let components = windowName.components(separatedBy: " - ")
                    return components.count > 1 ? components[1] : windowName
                }
            case .teams:
                if appNameLower.contains("teams") {
                    return windowName
                }
            default:
                if !windowName.isEmpty {
                    return windowName
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Public Methods
    func markCallAsLogged(_ callId: UUID) {
        if let index = activeCalls.firstIndex(where: { $0.id == callId }) {
            activeCalls.remove(at: index)
        }
    }
    
    func dismissCall(_ callId: UUID) {
        markCallAsLogged(callId)
    }
    
    func getSuggestedProject(for call: DetectedCall) -> String? {
        // Try to suggest a project based on call title
        let title = call.title?.lowercased() ?? ""
        
        if title.contains("standup") || title.contains("daily") {
            return "Meetings"
        } else if title.contains("review") {
            return "Code Review"
        } else if title.contains("planning") {
            return "Planning"
        } else if title.contains("interview") {
            return "Recruiting"
        } else if title.contains("client") || title.contains("customer") {
            return "Client Work"
        }
        
        return "Meetings"
    }
}

// MARK: - CGWindow Extensions
private let kCGWindowOwnerName = "kCGWindowOwnerName"
private let kCGWindowName = "kCGWindowName"
