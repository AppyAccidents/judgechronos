import Foundation

final class RulesEngine {
    static let shared = RulesEngine()
    
    func evaluate(session: Session, rules: [Rule]) -> RuleMatch? {
        // 1. Sort rules by priority (Descending: 100 before 1)
        let sortedRules = rules
            .filter { $0.isEnabled }
            .sorted { $0.priority > $1.priority }
        
        // 2. Iterate and find first match
        for rule in sortedRules {
            if matches(rule: rule, session: session) {
                // Return a match object describing what happened
                return RuleMatch(
                    id: UUID(),
                    ruleId: rule.id,
                    sessionId: session.id,
                    timestamp: Date(),
                    appliedChanges: describeChanges(rule: rule)
                )
            }
        }
        
        return nil
    }
    
    func apply(match: RuleMatch, to session: inout Session, using rules: [Rule]) {
        guard let rule = rules.first(where: { $0.id == match.ruleId }) else { return }
        
        // Apply actions only if manual override isn't present (or if we decide rules override empty Manual)
        // For now, let's assume Rule only applies if category is nil, OR if we want to support aggressive rules later.
        // Current logic: If session has NO manual category, apply rule.
        
        if session.categoryId == nil {
            session.categoryId = rule.targetCategoryId
        }
        
        if session.projectId == nil {
            session.projectId = rule.targetProjectId
        }
        
        if !rule.targetTagIds.isEmpty {
            session.tagIds.formUnion(rule.targetTagIds)
        }
        
        if rule.markAsPrivate {
            session.isPrivate = true
        }
    }
    
    private func matches(rule: Rule, session: Session) -> Bool {
        // App Name Match (Case insensitive contains or exact)
        // Using "Pattern" as simple substring match for MVP. Regex can come later.
        if let appPattern = rule.appNamePattern, !appPattern.isEmpty {
            if !session.sourceApp.localizedCaseInsensitiveContains(appPattern) {
                return false
            }
        }
        
        // Duration Match
        if let minDuration = rule.minDuration {
            if session.duration < minDuration {
                return false
            }
        }
        
        // Bundle ID & Window Title (Not fully supported in Session yet, logic placeholder)
        // To support Window Title, Session needs to know about it. RawEvent has it?
        // RawEvent has windowTitle, but Session aggregates multiple.
        // For now, we skip Window Title unless we aggregate it into Session.
        
        return true
    }
    
    private func describeChanges(rule: Rule) -> String {
        var changes: [String] = []
        if rule.targetCategoryId != nil { changes.append("Category") }
        if rule.targetProjectId != nil { changes.append("Project") }
        if !rule.targetTagIds.isEmpty { changes.append("Tags") }
        if rule.markAsPrivate { changes.append("Private") }
        return changes.joined(separator: ", ")
    }
}
