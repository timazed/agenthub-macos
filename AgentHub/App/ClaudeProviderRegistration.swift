import Foundation

extension ProviderRegistration {
    static let claude = ProviderRegistration(
        provider: .claude,
        capabilities: .available(
            authMethods: [.externalSetup],
            supportsChat: true,
            supportsScheduledTasks: false
        ),
        makeRuntime: { ClaudeRuntime() },
        makeAuthProviderClient: { _, paths in
            ClaudeAuthProviderClient(paths: paths)
        }
    )
}
