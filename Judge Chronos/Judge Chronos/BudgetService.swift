import Foundation

@MainActor
final class BudgetService {
    static let shared = BudgetService()

    private init() {}

    struct BudgetUsage {
        let timeUsed: TimeInterval
        let moneyUsed: Double
    }

    struct BudgetRemaining {
        let time: TimeInterval?
        let money: Double?
    }

    func budgetUsed(for projectId: UUID, dataStore: LocalDataStore) -> BudgetUsage {
        var projectIds = [projectId]
        projectIds.append(contentsOf: dataStore.descendantProjectIds(of: projectId))

        let totalTime = dataStore.sessions
            .filter { session in
                guard let pid = session.projectId else { return false }
                return projectIds.contains(pid) && !session.isBreak
            }
            .reduce(0) { $0 + $1.duration }

        let project = dataStore.projects.first { $0.id == projectId }
        let rate = project?.hourlyRate ?? dataStore.preferences.defaultHourlyRate ?? 0
        let moneyUsed = (totalTime / 3600) * rate

        return BudgetUsage(timeUsed: totalTime, moneyUsed: moneyUsed)
    }

    func budgetRemaining(for projectId: UUID, dataStore: LocalDataStore) -> BudgetRemaining {
        guard let project = dataStore.projects.first(where: { $0.id == projectId }) else {
            return BudgetRemaining(time: nil, money: nil)
        }

        let usage = budgetUsed(for: projectId, dataStore: dataStore)

        let timeRemaining: TimeInterval? = project.timeBudgetSeconds.map { $0 - usage.timeUsed }
        let moneyRemaining: Double? = project.moneyBudget.map { $0 - usage.moneyUsed }

        return BudgetRemaining(time: timeRemaining, money: moneyRemaining)
    }

    func isOverBudget(projectId: UUID, dataStore: LocalDataStore) -> Bool {
        let remaining = budgetRemaining(for: projectId, dataStore: dataStore)
        if let time = remaining.time, time < 0 { return true }
        if let money = remaining.money, money < 0 { return true }
        return false
    }

    func budgetPercentage(for projectId: UUID, dataStore: LocalDataStore) -> (time: Double?, money: Double?) {
        guard let project = dataStore.projects.first(where: { $0.id == projectId }) else {
            return (nil, nil)
        }

        let usage = budgetUsed(for: projectId, dataStore: dataStore)

        let timePct: Double? = project.timeBudgetSeconds.map { budget in
            guard budget > 0 else { return 0 }
            return usage.timeUsed / budget
        }

        let moneyPct: Double? = project.moneyBudget.map { budget in
            guard budget > 0 else { return 0 }
            return usage.moneyUsed / budget
        }

        return (timePct, moneyPct)
    }

    func clientBudgetUsed(for clientId: UUID, dataStore: LocalDataStore) -> BudgetUsage {
        let clientProjects = dataStore.projects.filter { $0.clientId == clientId }
        var totalTime: TimeInterval = 0
        var totalMoney: Double = 0

        for project in clientProjects {
            let usage = budgetUsed(for: project.id, dataStore: dataStore)
            totalTime += usage.timeUsed
            totalMoney += usage.moneyUsed
        }

        return BudgetUsage(timeUsed: totalTime, moneyUsed: totalMoney)
    }
}
