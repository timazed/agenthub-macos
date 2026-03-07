import Foundation

final class ProviderRegistry {
    private let paths: AppPaths
    private let authStore: AuthStore
    private let registrations: [AuthProvider: ProviderRegistration]

    init(
        paths: AppPaths,
        authStore: AuthStore,
        registrations: [ProviderRegistration] = [.codex] // NOTE add claude in here as a provider later on
    ) {
        self.paths = paths
        self.authStore = authStore
        self.registrations = Dictionary(uniqueKeysWithValues: registrations.map { ($0.provider, $0) })
    }

    var availableProviders: [AuthProvider] {
        AuthProvider.allCases.filter { registrations[$0] != nil }
    }

    func capabilities(for provider: AuthProvider) -> ProviderCapabilities {
        registration(for: provider).capabilities
    }

    func makeRuntime(for provider: AuthProvider) -> AssistantRuntime {
        registration(for: provider).makeRuntime()
    }

    func makeAuthManager(for provider: AuthProvider) -> AuthManaging {
        let runtime = makeRuntime(for: provider)
        let client = registration(for: provider).makeAuthProviderClient(runtime: runtime, paths: paths)
        return AuthManager(store: authStore, providerClient: client)
    }

    func currentProvider() -> AuthProvider {
        guard let provider = availableProviders.first else {
            fatalError("No providers registered")
        }
        return provider
    }

    private func registration(for provider: AuthProvider) -> ProviderRegistration {
        guard let registration = registrations[provider] else {
            fatalError("Missing provider registration for \(provider.rawValue)")
        }
        return registration
    }
}
