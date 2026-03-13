import Foundation

enum AppTheme: String, Codable, CaseIterable, Hashable {
    case `default`
    case bubbleGum

    var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .bubbleGum:
            return "Bubble Gum"
        }
    }

    var subtitle: String {
        switch self {
        case .default:
            return "Use the standard macOS light and dark appearance."
        case .bubbleGum:
            return "Animated candy-glass chat with pink, lilac, and cyan."
        }
    }
}

struct SupportedModel: Hashable, Identifiable {
    let id: String
    let displayName: String

    init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }

    static func displayName(for modelID: String) -> String {
        AppRuntimeConfig.supportedModels.first {
            $0.id.caseInsensitiveCompare(modelID) == .orderedSame
        }?.displayName ?? modelID
    }
}

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
    var theme: AppTheme
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case model
        case reasoningEffort
        case theme
        case updatedAt
    }

    init(
        model: String,
        reasoningEffort: ReasoningEffort,
        theme: AppTheme,
        updatedAt: Date
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.theme = theme
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        reasoningEffort = try container.decode(ReasoningEffort.self, forKey: .reasoningEffort)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .default
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    static let supportedModels: [SupportedModel] = [
        SupportedModel(id: "gpt-5.3-codex", displayName: "GPT-5.3-Codex"),
        SupportedModel(id: "gpt-5.4", displayName: "GPT-5.4"),
        SupportedModel(id: "gpt-5.3-codex-spark", displayName: "GPT-5.3-Codex-Spark"),
        SupportedModel(id: "gpt-5.2-codex", displayName: "GPT-5.2-Codex"),
        SupportedModel(id: "gpt-5.1-codex-max", displayName: "GPT-5.1-Codex-Max"),
        SupportedModel(id: "gpt-5.2", displayName: "GPT-5.2"),
        SupportedModel(id: "gpt-5.1-codex-mini", displayName: "GPT-5.1-Codex-Mini")
    ]

    static func `default`() -> AppRuntimeConfig {
        AppRuntimeConfig(
            model: "gpt-5.4",
            reasoningEffort: .medium,
            theme: .default,
            updatedAt: Date()
        )
    }
}
