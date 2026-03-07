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
    var defaultProvider: AuthProvider
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case model
        case reasoningEffort
        case defaultProvider
        case updatedAt
    }

    init(model: String, reasoningEffort: ReasoningEffort, defaultProvider: AuthProvider, updatedAt: Date) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.defaultProvider = defaultProvider
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        reasoningEffort = try container.decode(ReasoningEffort.self, forKey: .reasoningEffort)
        defaultProvider = try container.decodeIfPresent(AuthProvider.self, forKey: .defaultProvider) ?? .codex
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    static func `default`() -> AppRuntimeConfig {
        AppRuntimeConfig(
            model: "gpt-5.4",
            reasoningEffort: .medium,
            defaultProvider: .codex,
            updatedAt: Date()
        )
    }
}
