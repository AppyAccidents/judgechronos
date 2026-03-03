import Foundation

enum DistributionChannel: String {
    case direct
    case macAppStore = "mas"

    static var current: DistributionChannel {
        if let value = Bundle.main.object(forInfoDictionaryKey: "JCDistributionChannel") as? String,
           let channel = DistributionChannel(rawValue: value.lowercased()) {
            return channel
        }
        if let bundleId = Bundle.main.bundleIdentifier?.lowercased(),
           bundleId.contains("mas") {
            return .macAppStore
        }
        return .direct
    }

    var supportsKnowledgeCImport: Bool {
        self == .direct
    }

    var requiresFullDiskAccess: Bool {
        self == .direct
    }
}

struct ActivityCapabilities: Equatable {
    let supportsHistoricalImport: Bool
    let requiresFullDiskAccess: Bool
}
