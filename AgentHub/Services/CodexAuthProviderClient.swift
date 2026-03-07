import Foundation

final class CodexAuthProviderClient: AuthProviderClient {
    let provider: AuthProvider = .codex
    let capabilities = ProviderCapabilities.available(authMethods: [.deviceCode])

    private let runtime: AssistantRuntime
    private let paths: AppPaths
    private let loginCoordinator: CodexLoginCoordinator

    init(
        runtime: AssistantRuntime,
        paths: AppPaths,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.runtime = runtime
        self.paths = paths
        self.loginCoordinator = CodexLoginCoordinator(
            statusRefresher: { [runtime, paths] in
                let result = try runtime.checkLoginStatus(codexHome: paths.root.path)
                let now = Date()
                return AuthState(
                    provider: .codex,
                    status: result.isAuthenticated ? .authenticated : .unauthenticated,
                    accountLabel: result.accountEmail,
                    lastValidatedAt: result.isAuthenticated ? now : nil,
                    failureReason: result.isAuthenticated ? nil : result.message,
                    updatedAt: now
                )
            },
            paths: paths,
            bundle: bundle,
            fileManager: fileManager
        )
    }

    func refreshStatus() throws -> AuthState {
        let result = try runtime.checkLoginStatus(codexHome: paths.root.path)
        let now = Date()
        return AuthState(
            provider: .codex,
            status: result.isAuthenticated ? .authenticated : .unauthenticated,
            accountLabel: result.accountEmail,
            lastValidatedAt: result.isAuthenticated ? now : nil,
            failureReason: result.isAuthenticated ? nil : result.message,
            updatedAt: now
        )
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        try await loginCoordinator.startLogin()
    }

    func waitForLoginCompletion() async throws -> AuthState {
        try await loginCoordinator.waitForCompletion()
    }

    func cancelLogin() {
        loginCoordinator.cancel()
    }
}
