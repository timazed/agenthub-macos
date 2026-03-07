import Foundation

final class ProviderRegistry {
    private let paths: AppPaths
    private let runtimeConfigStore: AppRuntimeConfigStore
    private let authStore: AuthStore
    private let factories: [AuthProvider: ProviderFactory]

    init(
        paths: AppPaths,
        runtimeConfigStore: AppRuntimeConfigStore,
        authStore: AuthStore,
        factories: [ProviderFactory] = [CodexProviderFactory()]
    ) {
        self.paths = paths
        self.runtimeConfigStore = runtimeConfigStore
        self.authStore = authStore
        self.factories = Dictionary(uniqueKeysWithValues: factories.map { ($0.provider, $0) })
    }

    var availableProviders: [AuthProvider] {
        AuthProvider.allCases.filter { factories[$0] != nil }
    }

    func capabilities(for provider: AuthProvider) -> ProviderCapabilities {
        factory(for: provider).capabilities
    }

    func makeRuntime(for provider: AuthProvider) -> AssistantRuntime {
        factory(for: provider).makeRuntime()
    }

    func makeAuthManager(for provider: AuthProvider) -> AuthManaging {
        let runtime = makeRuntime(for: provider)
        let client = factory(for: provider).makeAuthProviderClient(runtime: runtime, paths: paths)
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

    private func factory(for provider: AuthProvider) -> ProviderFactory {
        guard let factory = factories[provider] else {
            fatalError("Missing provider factory for \(provider.rawValue)")
        }
        return factory
    }
}
