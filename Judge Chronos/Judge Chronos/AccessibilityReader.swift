import AppKit
import ApplicationServices
import Foundation

class AccessibilityReader: ObservableObject {
    static let shared = AccessibilityReader()
    
    @Published var isTrusted: Bool = AXIsProcessTrusted()
    
    private var pollingTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var lastRecordedTitle: String?
    private var lastRecordedApp: String?
    private var lastRecordedAt: Date?
    
    // Configurable polling interval
    private let pollInterval: TimeInterval = 15.0
    private let sameContextCooldown: TimeInterval = 20.0
    
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

        setupWorkspaceObserver(dataStore: dataStore)
        captureCurrentContext(dataStore: dataStore)
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.captureCurrentContext(dataStore: dataStore)
        }
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    private func setupWorkspaceObserver(dataStore: LocalDataStore) {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.captureCurrentContext(dataStore: dataStore)
        }
    }

    private func captureCurrentContext(dataStore: LocalDataStore) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier ?? "unknown.bundle.id"
        let pid = frontApp.processIdentifier

        if frontApp.activationPolicy != .regular {
            return
        }
        if bundleId == Bundle.main.bundleIdentifier {
            return
        }
        if bundleId.hasPrefix("com.apple.system") || bundleId == "com.apple.dock" || bundleId == "com.apple.finder" {
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let title = self.focusedWindowTitle(for: pid)
            DispatchQueue.main.async {
                self.recordContextIfNeeded(
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: title,
                    dataStore: dataStore
                )
            }
        }
    }

    private func focusedWindowTitle(for pid: pid_t) -> String? {
        let appRef = AXUIElementCreateApplication(pid)
        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
              let focusedWindowValue,
              CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let windowRef = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowRef, kAXTitleAttribute as CFString, &titleValue) == .success,
              let title = titleValue as? String,
              !title.isEmpty else {
            return nil
        }
        return title
    }

    @MainActor
    private func recordContextIfNeeded(appName: String, bundleId: String, windowTitle: String?, dataStore: LocalDataStore) {
        let now = Date()
        if !shouldRecordAndMarkContext(appName: appName, windowTitle: windowTitle, now: now) {
            return
        }

        let sanitizedTitle = windowTitle.map { ContextEvent.sanitize($0) }
        let event = ContextEvent(
            id: UUID(),
            timestamp: now,
            bundleId: bundleId,
            appName: appName,
            windowTitle: sanitizedTitle,
            documentPath: nil
        )
        dataStore.addContextEvent(event)
    }

    @MainActor
    func shouldRecordAndMarkContext(appName: String, windowTitle: String?, now: Date = Date()) -> Bool {
        if appName == lastRecordedApp, windowTitle == lastRecordedTitle,
           let lastRecordedAt,
           now.timeIntervalSince(lastRecordedAt) < sameContextCooldown {
            return false
        }
        lastRecordedApp = appName
        lastRecordedTitle = windowTitle
        lastRecordedAt = now
        return true
    }
}
