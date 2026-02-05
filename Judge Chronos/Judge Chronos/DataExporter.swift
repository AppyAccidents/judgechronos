import Foundation

struct ExportContainer: Encodable {
    let schemaVersion: Int
    let exportedAt: Date
    let data: LocalData
}

final class DataExporter {
    static let shared = DataExporter()
    
    // Schema version for future migration support
    private let currentSchemaVersion = 1
    
    func exportAllData(from dataStore: LocalDataStore) throws -> Data {
        // Create container with metadata
        let container = ExportContainer(
            schemaVersion: currentSchemaVersion,
            exportedAt: Date(),
            data: dataStore.snapshot()
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try encoder.encode(container)
    }
}
