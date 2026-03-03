import AppKit
import ApplicationServices
import Foundation

protocol ActivityIngestionProvider {
    var capabilities: ActivityCapabilities { get }
    func fetchIncremental(since lastImport: Date?) async throws -> [RawEvent]
}

#if !APPSTORE
final class KnowledgeCIngestionProvider: ActivityIngestionProvider {
    let capabilities = ActivityCapabilities(
        supportsHistoricalImport: true,
        requiresFullDiskAccess: true
    )

    func fetchIncremental(since lastImport: Date?) async throws -> [RawEvent] {
        try KnowledgeCReader.shared.fetchEvents(since: lastImport)
    }
}
#endif

@MainActor
final class ForegroundContextIngestionProvider: ActivityIngestionProvider {
    let capabilities = ActivityCapabilities(
        supportsHistoricalImport: false,
        requiresFullDiskAccess: false
    )

    private var workspaceObserver: NSObjectProtocol?
    private var timeline: [ContextEvent] = []
    private var lastContext: ContextEvent?
    private let minSegmentDuration: TimeInterval = 5

    init() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureCurrentContext()
            }
        }
        captureCurrentContext()
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func fetchIncremental(since lastImport: Date?) async throws -> [RawEvent] {
        captureCurrentContext()
        guard !timeline.isEmpty else { return [] }

        let cutoff = lastImport ?? .distantPast
        var events: [RawEvent] = []
        let now = Date()
        let sequence = timeline + [ContextEvent(
            id: UUID(),
            timestamp: now,
            bundleId: timeline.last?.bundleId ?? "unknown.bundle.id",
            appName: timeline.last?.appName ?? "Unknown",
            windowTitle: timeline.last?.windowTitle,
            documentPath: nil
        )]

        for index in 0..<(sequence.count - 1) {
            let current = sequence[index]
            let next = sequence[index + 1]
            let duration = next.timestamp.timeIntervalSince(current.timestamp)
            guard duration >= minSegmentDuration else { continue }
            guard next.timestamp > cutoff else { continue }

            let titlePart = current.windowTitle?.isEmpty == false ? " — \(current.windowTitle!)" : ""
            let appName = "\(current.appName)\(titlePart)"
            let metadata = "fg|\(current.bundleId)|\(Int(current.timestamp.timeIntervalSince1970))|\(Int(next.timestamp.timeIntervalSince1970))|\(appName)"
            events.append(
                RawEvent(
                    id: UUID(),
                    timestamp: current.timestamp,
                    duration: duration,
                    bundleId: current.bundleId,
                    appName: appName,
                    windowTitle: current.windowTitle,
                    source: .appUsage,
                    metadataHash: String(metadata.hashValue),
                    importedAt: now
                )
            )
        }

        return events
    }

    private func captureCurrentContext() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier ?? "unknown.bundle.id"
        if frontApp.activationPolicy != .regular { return }
        if bundleId == Bundle.main.bundleIdentifier { return }

        let title = focusedWindowTitle(for: frontApp.processIdentifier)
        let context = ContextEvent(
            id: UUID(),
            timestamp: Date(),
            bundleId: bundleId,
            appName: appName,
            windowTitle: title.map { ContextEvent.sanitize($0) },
            documentPath: nil
        )
        if let last = lastContext,
           last.appName == context.appName,
           last.windowTitle == context.windowTitle,
           context.timestamp.timeIntervalSince(last.timestamp) < 10 {
            return
        }
        lastContext = context
        timeline.append(context)
        if timeline.count > 500 {
            timeline.removeFirst(timeline.count - 500)
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
}
