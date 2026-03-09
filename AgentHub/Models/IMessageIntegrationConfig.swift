import Foundation

struct IMessageIntegrationConfig: Codable, Hashable {
    var isEnabled: Bool
    var allowedHandles: [String]
    var updatedAt: Date

    static func `default`() -> IMessageIntegrationConfig {
        IMessageIntegrationConfig(
            isEnabled: false,
            allowedHandles: [],
            updatedAt: Date()
        )
    }
}
