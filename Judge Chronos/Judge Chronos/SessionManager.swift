import Foundation

final class SessionManager {
    static let shared = SessionManager()
    
    // Threshold to merge adjacent events of the same app (in seconds).
    // If gap is less than this, they are considered one continuous session.
    private let mergeThreshold: TimeInterval = 60
    
    func deriveSessions(from rawEvents: [RawEvent]) -> [Session] {
        let sortedEvents = rawEvents.sorted { $0.timestamp < $1.timestamp }
        var sessions: [Session] = []
        
        var currentSession: Session?
        
        for event in sortedEvents {
            if let existing = currentSession {
                if canMerge(event, into: existing) {
                    // Merge: Extend end time and add reference
                    currentSession?.endTime = event.timestamp.addingTimeInterval(event.duration)
                    currentSession?.rawEventIds.append(event.id)
                } else {
                    // Finalize current session
                    sessions.append(existing)
                    // Start new session
                    currentSession = createSession(from: event)
                }
            } else {
                // Start first session
                currentSession = createSession(from: event)
            }
        }
        
        // Append last session
        if let last = currentSession {
            sessions.append(last)
        }
        
        return sessions
    }
    
    private func createSession(from event: RawEvent) -> Session {
        Session(
            id: UUID(),
            startTime: event.timestamp,
            endTime: event.timestamp.addingTimeInterval(event.duration),
            sourceApp: event.appName,
            bundleId: event.bundleId,
            lastWindowTitle: event.windowTitle,
            windowTitleSamples: event.windowTitle.map { [$0] } ?? [],
            overlappingMeetingIds: [],
            rawEventIds: [event.id],
            projectId: nil,
            inferredProjectId: nil,
            inferenceConfidence: 0,
            categoryId: nil,
            tagIds: [],
            note: nil,
            isPrivate: false,
            isIdle: event.source == .idle
        )
    }
    
    private func canMerge(_ event: RawEvent, into session: Session) -> Bool {
        // 1. Must be same app
        guard event.appName == session.sourceApp else { return false }
        
        // 2. Must be same idle state
        let eventIsIdle = (event.source == .idle)
        guard eventIsIdle == session.isIdle else { return false }
        
        // 3. Must be within time threshold
        // Gap = event.start - session.end
        let gap = event.timestamp.timeIntervalSince(session.endTime)
        
        // Allow gap to be slightly negative (overlapping) or within threshold
        return gap <= mergeThreshold
    }
    
    func updateSessions(_ sessions: inout [Session], with newRawEvents: [RawEvent]) -> Set<UUID> {
        let sortedNew = newRawEvents.sorted { $0.timestamp < $1.timestamp }
        guard !sortedNew.isEmpty else { return [] }

        var changedSessionIds: Set<UUID> = []
        var remainingEvents = sortedNew

        if var lastSession = sessions.last, let firstEvent = remainingEvents.first {
            if canMerge(firstEvent, into: lastSession) {
                lastSession.endTime = firstEvent.timestamp.addingTimeInterval(firstEvent.duration)
                lastSession.rawEventIds.append(firstEvent.id)
                if let title = firstEvent.windowTitle, !title.isEmpty {
                    lastSession.lastWindowTitle = title
                    if !lastSession.windowTitleSamples.contains(title) {
                        lastSession.windowTitleSamples.append(title)
                    }
                }
                if let bundleId = firstEvent.bundleId {
                    lastSession.bundleId = bundleId
                }
                sessions[sessions.count - 1] = lastSession
                changedSessionIds.insert(lastSession.id)
                remainingEvents.removeFirst()
            }
        }

        let newSessions = deriveSessions(from: remainingEvents)
        sessions.append(contentsOf: newSessions)
        for session in newSessions {
            changedSessionIds.insert(session.id)
        }

        return changedSessionIds
    }
}
