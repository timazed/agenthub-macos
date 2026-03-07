import Foundation

struct ProviderCapabilities: Codable, Hashable {
    var authMethods: [AuthMethod]
    var supportsChat: Bool
    var supportsScheduledTasks: Bool
    var isAvailable: Bool
    var availabilityMessage: String?

    static func available(
        authMethods: [AuthMethod],
        supportsChat: Bool = true,
        supportsScheduledTasks: Bool = true
    ) -> ProviderCapabilities {
        ProviderCapabilities(
            authMethods: authMethods,
            supportsChat: supportsChat,
            supportsScheduledTasks: supportsScheduledTasks,
            isAvailable: true,
            availabilityMessage: nil
        )
    }

    static func unavailable(message: String) -> ProviderCapabilities {
        ProviderCapabilities(
            authMethods: [],
            supportsChat: false,
            supportsScheduledTasks: false,
            isAvailable: false,
            availabilityMessage: message
        )
    }
}
