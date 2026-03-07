import Foundation

struct CodexProviderFactory: ProviderFactory {
    let provider: AuthProvider = .codex
    let capabilities = ProviderCapabilities.available(authMethods: [.browser])

    func makeRuntime() -> AssistantRuntime {
        CodexCLIRuntime()
    }

    func makeAuthProviderClient(runtime: AssistantRuntime, paths: AppPaths) -> AuthProviderClient {
        CodexAuthProviderClient(runtime: runtime, paths: paths)
    }
}
