import Foundation

final class SelectableAuthManager: AuthManaging {
    private let registry: ProviderRegistry
    private let lock = NSLock()
    private var managers: [AuthProvider: AuthManaging] = [:]

    init(registry: ProviderRegistry) {
        self.registry = registry
    }

    var currentProvider: AuthProvider {
        (try? registry.currentProvider()) ?? .codex
    }

    var availableProviders: [AuthProvider] {
        registry.availableProviders
    }

    var capabilities: ProviderCapabilities {
        registry.capabilities(for: currentProvider)
    }

    func loadCachedState() throws -> AuthState {
        try manager(for: currentProvider).loadCachedState()
    }

    @discardableResult
    func refreshStatus() throws -> AuthState {
        try manager(for: currentProvider).refreshStatus()
    }

    func requireAuthenticated() throws {
        try manager(for: currentProvider).requireAuthenticated()
    }

    @discardableResult
    func selectProvider(_ provider: AuthProvider) throws -> AuthState {
        let state = try registry.setCurrentProvider(provider)
        _ = manager(for: provider)
        return state
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        try await manager(for: currentProvider).startLogin()
    }

    func waitForLoginCompletion() async throws -> AuthState {
        try await manager(for: currentProvider).waitForLoginCompletion()
    }

    func cancelLogin() {
        manager(for: currentProvider).cancelLogin()
    }

    private func manager(for provider: AuthProvider) -> AuthManaging {
        lock.lock()
        defer { lock.unlock() }
        if let manager = managers[provider] {
            return manager
        }
        let manager = registry.makeAuthManager(for: provider)
        managers[provider] = manager
        return manager
    }
}
