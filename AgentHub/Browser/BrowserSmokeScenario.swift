import Foundation

struct BrowserSmokeScenarioDefinition: Codable, Equatable, Identifiable {
    let id: String
    let category: String
    let title: String
    let goalText: String
    let initialURL: String?
    let matchAny: [String]
    let expectedOutcomes: [String]
    let notes: String?
}

enum BrowserSmokeScenarioManifest {
    static func load(from url: URL) throws -> [BrowserSmokeScenarioDefinition] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([BrowserSmokeScenarioDefinition].self, from: data)
    }
}

struct BrowserScenarioMetadata: Codable, Equatable {
    let id: String
    let title: String
    let category: String
}

struct BrowserScenarioRunSummary: Codable, Equatable {
    let scenarioID: String
    let category: String
    let outcome: String
    let finalSummary: String
}
