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

final class AuthManager {
    private let store: AuthStore
    private let providerClient: AuthProviderClient

    init(store: AuthStore, providerClient: AuthProviderClient) {
        self.store = store
        self.providerClient = providerClient
    }

    func loadCachedState() throws -> AuthState {
        try store.loadOrCreateDefault()
    }

    @discardableResult
    func refreshStatus() throws -> AuthState {
        do {
            let state = try providerClient.refreshStatus()
            try store.save(state)
            return state
        } catch let error as AssistantRuntimeError {
            let state = AuthState(
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
