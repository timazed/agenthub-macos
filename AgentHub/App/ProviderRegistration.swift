import Foundation

struct ProviderRegistration {
    let provider: AuthProvider
    let capabilities: ProviderCapabilities

    private let runtimeBuilder: () -> AssistantRuntime
    private let authClientBuilder: @MainActor (AssistantRuntime, AppPaths) -> AuthProviderClient

    init(
        provider: AuthProvider,
        capabilities: ProviderCapabilities,
        makeRuntime: @escaping () -> AssistantRuntime,
        makeAuthProviderClient: @escaping @MainActor (AssistantRuntime, AppPaths) -> AuthProviderClient
    ) {
        self.provider = provider
        self.capabilities = capabilities
        self.runtimeBuilder = makeRuntime
        self.authClientBuilder = makeAuthProviderClient
    }

    func makeRuntime() -> AssistantRuntime {
        runtimeBuilder()
    }

    @MainActor
    func makeAuthProviderClient(runtime: AssistantRuntime, paths: AppPaths) -> AuthProviderClient {
        authClientBuilder(runtime, paths)
    }
}
