import Foundation

enum CodexAuthServiceError: LocalizedError {
    case unauthenticated(String?)
    case statusCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unauthenticated(reason):
            return reason ?? "Codex login is required"
        case let .statusCheckFailed(message):
            return message
        }
    }
}

final class CodexAuthService {
    private let store: CodexAuthStore
    private let runtime: CodexRuntime
    private let paths: AppPaths

    init(store: CodexAuthStore, runtime: CodexRuntime, paths: AppPaths) {
        self.store = store
        self.runtime = runtime
        self.paths = paths
    }

    func loadCachedState() throws -> CodexAuthState {
        try store.loadOrCreateDefault()
    }

    @discardableResult
    func refreshStatus() throws -> CodexAuthState {
        do {
            let result = try runtime.checkLoginStatus(codexHome: paths.root.path)
            let now = Date()
            let state = CodexAuthState(
                status: result.isAuthenticated ? .authenticated : .unauthenticated,
                accountEmail: result.accountEmail,
                lastValidatedAt: result.isAuthenticated ? now : nil,
                failureReason: result.isAuthenticated ? nil : result.message,
                updatedAt: now
            )
            try store.save(state)
            return state
        } catch let error as CodexRuntimeError {
            let now = Date()
            let state = CodexAuthState(
                status: .failed,
                accountEmail: nil,
                lastValidatedAt: nil,
                failureReason: error.localizedDescription,
                updatedAt: now
            )
            try? store.save(state)
            throw CodexAuthServiceError.statusCheckFailed(error.localizedDescription)
        } catch {
            let now = Date()
            let state = CodexAuthState(
                status: .failed,
                accountEmail: nil,
                lastValidatedAt: nil,
                failureReason: error.localizedDescription,
                updatedAt: now
            )
            try? store.save(state)
            throw CodexAuthServiceError.statusCheckFailed(error.localizedDescription)
        }
    }

    func requireAuthenticated() throws {
        let state = try refreshStatus()
        guard state.isAuthenticated else {
            throw CodexAuthServiceError.unauthenticated(state.failureReason)
        }
    }
}
