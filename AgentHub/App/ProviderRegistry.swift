import Foundation

final class ProviderRegistry {
    private let paths: AppPaths
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let authStore: AuthStore
    private let registrations: [AuthProvider: ProviderRegistration]

    init(
        paths: AppPaths,
        runtimeConfigStore: AppRuntimeConfigStore,
        authStore: AuthStore,
        registrations: [ProviderRegistration] = [.codex]
    ) {
        self.paths = paths
        self.runtimeConfigStore = runtimeConfigStore
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

    func currentProvider() throws -> AuthProvider {
        let configured = try runtimeConfigStore.loadOrCreateDefault().defaultProvider
        return availableProviders.contains(configured) ? configured : .codex
    }

    @discardableResult
    func setCurrentProvider(_ provider: AuthProvider) throws -> AuthState {
        guard availableProviders.contains(provider) else {
            throw AuthManagerError.statusCheckFailed("Unsupported provider: \(provider.displayName)")
        }
        var config = try runtimeConfigStore.loadOrCreateDefault()
        config.defaultProvider = provider
        config.updatedAt = Date()
        try runtimeConfigStore.save(config)
        return try makeAuthManager(for: provider).loadCachedState()
    }

    @discardableResult
    func normalizeCurrentProviderIfNeeded() throws -> AuthProvider {
        let provider = try currentProvider()
        var config = try runtimeConfigStore.loadOrCreateDefault()
        guard config.defaultProvider != provider else { return provider }
        config.defaultProvider = provider
        config.updatedAt = Date()
        try runtimeConfigStore.save(config)
        return provider
    }

    private func registration(for provider: AuthProvider) -> ProviderRegistration {
        guard let registration = registrations[provider] else {
            fatalError("Missing provider registration for \(provider.rawValue)")
        }
        return registration
    }
}
