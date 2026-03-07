import Foundation

enum ReasoningEffort: String, Codable, CaseIterable, Hashable {
    case low
    case medium
    case high
    case max

    var displayName: String {
        rawValue.capitalized
    }
}

struct AppRuntimeConfig: Codable, Hashable {
    var model: String
    var reasoningEffort: ReasoningEffort
    var updatedAt: Date

    static func `default`() -> AppRuntimeConfig {
        AppRuntimeConfig(
            model: "gpt-5.4",
            reasoningEffort: .medium,
            updatedAt: Date()
        )
    }
}
