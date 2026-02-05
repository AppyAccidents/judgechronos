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
        return Session(
            id: UUID(),
            startTime: event.timestamp,
            endTime: event.timestamp.addingTimeInterval(event.duration),
            sourceApp: event.appName,
            rawEventIds: [event.id],
            projectId: nil,
            categoryId: nil,
            tagIds: [],
            note: nil,
            isPrivate: false,
            // If raw event source is idle, mark session as idle
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
    
    func updateSessions(_ sessions: inout [Session], with newRawEvents: [RawEvent], rules: [Rule]) -> [RuleMatch] {
        // 1. Sort new events
        let sortedNew = newRawEvents.sorted { $0.timestamp < $1.timestamp }
        guard !sortedNew.isEmpty else { return }
        
        // 2. Try to merge first new event into the last existing session
        var remainingEvents = sortedNew
        
        if var lastSession = sessions.last, let firstEvent = remainingEvents.first {
            if canMerge(firstEvent, into: lastSession) {
                // Determine if we need to update the mutable copy in the array
                // Update session end time and events
                lastSession.endTime = firstEvent.timestamp.addingTimeInterval(firstEvent.duration)
                lastSession.rawEventIds.append(firstEvent.id)
                
                // Replace the last session in the array with updated version
                // Re-evaluate rules on the updated session (in case duration change triggers rule)
                // Note: We need access to rules here. For now, we'll fetch from LocalDataStore.shared? 
                // Better Design: Pass rules into updateSessions.
                
                sessions[sessions.count - 1] = lastSession
                
                // Remove this event from processing list
                remainingEvents.removeFirst()
            }
        }
        
        // 3. Derive new sessions from remaining events
        var newSessions = deriveSessions(from: remainingEvents)
        
        // 4. Update the input sessions
        sessions.append(contentsOf: newSessions)
        
        // 5. Apply rules to newly added/modified sessions
        // For efficiency, we could track *which* sessions changed, but for now we can scan.
        // Or better: The caller calls applyRules() after updateSessions().
        // Let's integrate it here to be safe and atomic.
        return applyRules(to: &sessions, rules: rules)
    }
    
    // START Phase 3 Integration
    func applyRules(to sessions: inout [Session], rules: [Rule]) -> [RuleMatch] {
        var matches: [RuleMatch] = []
        for i in 0..<sessions.count {
            // Only apply rules if no manual category is set (Strict "Don't Lie" Policy)
            // Or if we define that rules can overwrite empty fields.
            if sessions[i].categoryId == nil {
                if let match = RulesEngine.shared.evaluate(session: sessions[i], rules: rules) {
                    RulesEngine.shared.apply(match: match, to: &sessions[i], using: rules)
                    matches.append(match)
                }
            }
        }
        return matches
    }
}
