import AppKit
import ApplicationServices
import Foundation

class AccessibilityReader: ObservableObject {
    static let shared = AccessibilityReader()
    
    @Published var isTrusted: Bool = AXIsProcessTrusted()
    
    private var pollingTimer: Timer?
    private var lastRecordedTitle: String?
    private var lastRecordedApp: String?
    
    // Configurable polling interval
    private let pollInterval: TimeInterval = 5.0
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        isTrusted = AXIsProcessTrusted()
    }
    
    func promptForPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func startPolling(dataStore: LocalDataStore) {
        stopPolling()
        
        // Only poll if we have permissions
        guard isTrusted else { return }
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollCurrentWindow(dataStore: dataStore)
            }
        }
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    @MainActor
    private func pollCurrentWindow(dataStore: LocalDataStore) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier ?? "unknown.bundle.id"
        let pid = frontApp.processIdentifier
        
        var windowTitle: String? = nil
        
        // Accessibility API to get window title
        let appRef = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        
        // Get "FocusedWindow" first
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &value) == .success {
            let windowRef = value as! AXUIElement
            // Get "Title" of that window
            if AXUIElementCopyAttributeValue(windowRef, kAXTitleAttribute as CFString, &value) == .success,
               let title = value as? String, !title.isEmpty {
                windowTitle = title
            }
        }
        
        // Debounce: Only save if changed or enough time passed? 
        // For Phase 8 MVP: Save on change.
        if appName != lastRecordedApp || windowTitle != lastRecordedTitle {
            let sanitizedTitle = windowTitle.map { ContextEvent.sanitize($0) }
            
            let event = ContextEvent(
                id: UUID(),
                timestamp: Date(),
                bundleId: bundleId,
                appName: appName,
                windowTitle: sanitizedTitle,
                documentPath: nil // Document path requires kAXDocumentAttribute, left for later
            )
            
            dataStore.addContextEvent(event)
            
            lastRecordedApp = appName
            lastRecordedTitle = windowTitle
        }
    }
}
