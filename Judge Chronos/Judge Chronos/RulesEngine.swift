import Foundation

final class RulesEngine {
    static let shared = RulesEngine()
    
    func evaluate(session: Session, rules: [Rule]) -> RuleMatch? {
        if let evaluation = RuleMatcher.shared.evaluate(session: session, rules: rules) {
            return RuleMatch(
                id: UUID(),
                ruleId: evaluation.rule.id,
                sessionId: session.id,
                timestamp: Date(),
                appliedChanges: "\(describeChanges(rule: evaluation.rule)) [\(evaluation.reason)]"
            )
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
    
    private func describeChanges(rule: Rule) -> String {
        var changes: [String] = []
        if rule.targetCategoryId != nil { changes.append("Category") }
        if rule.targetProjectId != nil { changes.append("Project") }
        if !rule.targetTagIds.isEmpty { changes.append("Tags") }
        if rule.markAsPrivate { changes.append("Private") }
        return changes.joined(separator: ", ")
    }
}
