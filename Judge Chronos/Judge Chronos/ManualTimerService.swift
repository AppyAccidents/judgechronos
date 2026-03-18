import Foundation

@MainActor
final class ManualTimerService: ObservableObject {
    static let shared = ManualTimerService()

    private init() {}

    func startTimer(
        dataStore: LocalDataStore,
        projectId: UUID? = nil,
        activityId: UUID? = nil,
        description: String? = nil,
        isBillable: Bool = true
    ) -> ManualTimer {
        let timer = ManualTimer(
            projectId: projectId,
            activityId: activityId,
            description: description,
            startedAt: Date(),
            isBillable: isBillable
        )
        dataStore.addManualTimer(timer)
        return timer
    }

    func stopTimer(id: UUID, dataStore: LocalDataStore) {
        dataStore.stopManualTimer(id: id)
    }

    func activeTimers(dataStore: LocalDataStore) -> [ManualTimer] {
        dataStore.activeTimers
    }
}
