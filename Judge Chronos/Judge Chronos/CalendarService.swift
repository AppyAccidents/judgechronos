import EventKit
import Foundation

enum CalendarServiceError: Error {
    case accessDenied
}

final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    var hasAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    func requestAccess() async throws {
        if hasAccess { return }
        if #available(macOS 14.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            if !granted { throw CalendarServiceError.accessDenied }
        } else {
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestAccess(to: .event) { allowed, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: allowed)
                    }
                }
            }
            if !granted { throw CalendarServiceError.accessDenied }
        }
    }

    func fetchEvents(from startDate: Date, to endDate: Date) throws -> [EKEvent] {
        guard hasAccess else { throw CalendarServiceError.accessDenied }
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return store.events(matching: predicate)
    }
}
