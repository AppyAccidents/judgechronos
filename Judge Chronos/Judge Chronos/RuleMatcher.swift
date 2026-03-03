import Foundation

struct RuleEvaluation {
    let rule: Rule
    let reason: String
}

final class RuleMatcher {
    static let shared = RuleMatcher()

    func evaluate(session: Session, rules: [Rule]) -> RuleEvaluation? {
        let sorted = rules
            .filter { $0.isEnabled }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.priority > rhs.priority
            }

        for rule in sorted where matches(rule: rule, session: session) {
            return RuleEvaluation(rule: rule, reason: describeMatch(rule: rule, session: session))
        }
        return nil
    }

    func matches(rule: Rule, session: Session) -> Bool {
        if let appPattern = normalized(rule.appNamePattern),
           !session.sourceApp.localizedCaseInsensitiveContains(appPattern) {
            return false
        }

        if let bundlePattern = normalized(rule.bundleIdPattern) {
            guard let bundleId = normalized(session.bundleId),
                  bundleId.contains(bundlePattern) else {
                return false
            }
        }

        if let titlePattern = normalized(rule.windowTitlePattern) {
            let haystack = normalized(session.lastWindowTitle) ?? normalized(session.windowTitleSamples.joined(separator: " ")) ?? ""
            if !haystack.contains(titlePattern) {
                return false
            }
        }

        if let minDuration = rule.minDuration, session.duration < minDuration {
            return false
        }

        return true
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private func describeMatch(rule: Rule, session: Session) -> String {
        var reasons: [String] = []
        if let appPattern = normalized(rule.appNamePattern), session.sourceApp.lowercased().contains(appPattern) {
            reasons.append("app")
        }
        if let bundlePattern = normalized(rule.bundleIdPattern),
           let bundle = normalized(session.bundleId),
           bundle.contains(bundlePattern) {
            reasons.append("bundle")
        }
        if let titlePattern = normalized(rule.windowTitlePattern) {
            let titles = (session.lastWindowTitle ?? "") + " " + session.windowTitleSamples.joined(separator: " ")
            if titles.lowercased().contains(titlePattern) {
                reasons.append("title")
            }
        }
        if rule.minDuration != nil {
            reasons.append("duration")
        }
        if reasons.isEmpty {
            reasons.append("default")
        }
        return reasons.joined(separator: "+")
    }
}
