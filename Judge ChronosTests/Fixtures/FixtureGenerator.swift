import Foundation
@testable import Judge_Chronos

enum FixtureGenerator {
    static func createRawEvent(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        duration: TimeInterval = 60,
        bundleId: String = "com.apple.Safari",
        appName: String = "Safari",
        windowTitle: String? = "Judge Chronos GitHub",
        source: ActivityEventSource = .appUsage
    ) -> RawEvent {
        let metadata = "\(timestamp.timeIntervalSince1970)|\(bundleId)|\(source.rawValue)"
        let hash = String(metadata.hashValue)
        
        return RawEvent(
            id: id,
            timestamp: timestamp,
            duration: duration,
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            source: source,
            metadataHash: hash,
            importedAt: Date()
        )
    }
    
    static func createSession(
        from event: RawEvent,
        projectId: UUID? = nil,
        categoryId: UUID? = nil
    ) -> Session {
        return Session(
            id: UUID(),
            startTime: event.timestamp,
            endTime: event.timestamp.addingTimeInterval(event.duration),
            sourceApp: event.appName,
            rawEventIds: [event.id],
            projectId: projectId,
            categoryId: categoryId,
            tagIds: [],
            note: nil,
            isPrivate: false,
            isIdle: false
        )
    }
}
