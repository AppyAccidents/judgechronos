import Foundation

struct MeetingContext {
    let id: String
    let startDate: Date
    let endDate: Date
    let title: String?
}

final class ContextFusionService {
    static let shared = ContextFusionService()

    private let maxTitleSamples = 5

    func enrichSessions(
        sessions: [Session],
        contextEvents: [ContextEvent],
        meetings: [MeetingContext]
    ) -> [Session] {
        guard !sessions.isEmpty else { return [] }
        let sortedContext = contextEvents.sorted { $0.timestamp < $1.timestamp }
        return sessions.map { session in
            enrich(session: session, contextEvents: sortedContext, meetings: meetings)
        }
    }

    private func enrich(session: Session, contextEvents: [ContextEvent], meetings: [MeetingContext]) -> Session {
        guard !session.isIdle else { return resetInference(on: session) }

        let lowerBound = session.startTime.addingTimeInterval(-60)
        let upperBound = session.endTime.addingTimeInterval(60)
        let candidates = contextEvents.filter { event in
            event.timestamp >= lowerBound &&
            event.timestamp <= upperBound &&
            event.appName.localizedCaseInsensitiveContains(session.sourceApp)
        }

        let bundle = mostFrequent(candidates.map(\.bundleId))
        let titlesOrdered = candidates
            .compactMap(\.windowTitle)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let titleSamples = Array(NSOrderedSet(array: titlesOrdered).array as? [String] ?? []).suffix(maxTitleSamples)
        let meetingIds = meetings
            .filter { overlaps(startA: session.startTime, endA: session.endTime, startB: $0.startDate, endB: $0.endDate) }
            .map(\.id)
            .sorted()

        var updated = session
        updated.bundleId = bundle
        updated.windowTitleSamples = Array(titleSamples)
        updated.lastWindowTitle = titleSamples.last
        updated.overlappingMeetingIds = meetingIds
        updated.inferenceConfidence = inferenceConfidence(hasBundle: bundle != nil, hasTitle: !titleSamples.isEmpty, hasMeeting: !meetingIds.isEmpty)
        return updated
    }

    func suggestAutomaticCategoryName(for session: Session) -> String? {
        guard !session.isIdle else { return nil }
        if !session.overlappingMeetingIds.isEmpty {
            return "Meetings"
        }

        let app = session.sourceApp.lowercased()
        let titleText = ((session.lastWindowTitle ?? "") + " " + session.windowTitleSamples.joined(separator: " ")).lowercased()
        let bundle = session.bundleId?.lowercased() ?? ""

        if app.contains("terminal") || app.contains("ghostty") || app.contains("iterm") || app.contains("warp") || bundle.contains("terminal") {
            return "Development"
        }
        if app.contains("code") || app.contains("xcode") || bundle.contains("vscode") || bundle.contains("xcode") {
            return "Development"
        }
        if app.contains("jira") || bundle.contains("jira") || titleText.contains("jira") || titleText.contains("ticket") || titleText.contains("sprint") {
            return "Project Management"
        }
        if app.contains("slack") || app.contains("teams") || app.contains("discord") {
            return "Communication"
        }
        return nil
    }

    private func resetInference(on session: Session) -> Session {
        var updated = session
        updated.bundleId = nil
        updated.lastWindowTitle = nil
        updated.windowTitleSamples = []
        updated.overlappingMeetingIds = []
        updated.inferenceConfidence = 0
        return updated
    }

    private func overlaps(startA: Date, endA: Date, startB: Date, endB: Date) -> Bool {
        startA < endB && endA > startB
    }

    private func inferenceConfidence(hasBundle: Bool, hasTitle: Bool, hasMeeting: Bool) -> Double {
        var value = 0.4
        if hasBundle { value += 0.25 }
        if hasTitle { value += 0.25 }
        if hasMeeting { value += 0.1 }
        return min(value, 1)
    }

    private func mostFrequent(_ values: [String]) -> String? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }?.key
    }
}
