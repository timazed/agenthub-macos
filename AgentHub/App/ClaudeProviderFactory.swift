import Foundation

struct ClaudeProviderFactory: ProviderFactory {
    let provider: AuthProvider = .claude
    let capabilities = ProviderCapabilities.available(
        authMethods: [.externalSetup],
        supportsChat: true,
        supportsScheduledTasks: false
    )

    func makeRuntime() -> AssistantRuntime {
        ClaudeRuntime()
    }

    func makeAuthProviderClient(runtime: AssistantRuntime, paths: AppPaths) -> AuthProviderClient {
        ClaudeAuthProviderClient(paths: paths)
    }
}
