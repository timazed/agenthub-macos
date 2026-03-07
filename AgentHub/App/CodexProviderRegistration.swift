import Foundation

extension ProviderRegistration {
    static let codex = ProviderRegistration(
        provider: .codex,
        capabilities: .available(authMethods: [.browser]),
        makeRuntime: { CodexCLIRuntime() },
        makeAuthProviderClient: { runtime, paths in
            CodexAuthProviderClient(runtime: runtime, paths: paths)
        }
    )
}
