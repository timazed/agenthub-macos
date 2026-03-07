import Foundation

enum AuthManagerError: LocalizedError {
    case unauthenticated(String?)
    case statusCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unauthenticated(reason):
            return reason ?? "Login is required"
        case let .statusCheckFailed(message):
            return message
        }
    }
}

final class AuthManager: AuthManaging {
    private let store: AuthStore
    private let providerClient: AuthProviderClient

    init(store: AuthStore, providerClient: AuthProviderClient) {
        self.store = store
        self.providerClient = providerClient
    }

    var currentProvider: AuthProvider {
        providerClient.provider
    }

    var availableProviders: [AuthProvider] {
        [providerClient.provider]
    }

    var capabilities: ProviderCapabilities {
        providerClient.capabilities
    }

    func loadCachedState() throws -> AuthState {
        try store.loadOrCreateDefault(provider: providerClient.provider)
    }

    @discardableResult
    func refreshStatus() throws -> AuthState {
        do {
            let state = try providerClient.refreshStatus()
            try store.save(state)
            return state
        } catch let error as AssistantRuntimeError {
            let state = AuthState(
                provider: providerClient.provider,
                status: .failed,
                accountLabel: nil,
                lastValidatedAt: nil,
                failureReason: error.localizedDescription,
                updatedAt: Date()
            )
            try? store.save(state)
            throw AuthManagerError.statusCheckFailed(error.localizedDescription)
        } catch {
            let state = AuthState(
                provider: providerClient.provider,
                status: .failed,
                accountLabel: nil,
                lastValidatedAt: nil,
                failureReason: error.localizedDescription,
                updatedAt: Date()
            )
            try? store.save(state)
            throw AuthManagerError.statusCheckFailed(error.localizedDescription)
        }
    }

    func requireAuthenticated() throws {
        let state = try refreshStatus()
        guard state.isAuthenticated else {
            throw AuthManagerError.unauthenticated(state.failureReason)
        }
    }

    @discardableResult
    func selectProvider(_ provider: AuthProvider) throws -> AuthState {
        guard provider == providerClient.provider else {
            throw AuthManagerError.statusCheckFailed("Unsupported provider: \(provider.displayName)")
        }
        return try loadCachedState()
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        try await providerClient.startLogin()
    }

    func waitForLoginCompletion() async throws -> AuthState {
        let state = try await providerClient.waitForLoginCompletion()
        try store.save(state)
        return state
    }

    func cancelLogin() {
        providerClient.cancelLogin()
    }
}
