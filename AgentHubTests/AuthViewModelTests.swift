import Foundation
import Testing
@testable import AgentHub

@MainActor
struct AuthViewModelTests {
    @Test
    func startupRefreshMarksAuthenticatedState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = CodexAuthStore(paths: paths)
        let authService = CodexAuthService(
            store: store,
            runtime: AuthViewModelStubRuntime(loginStatus: .init(isAuthenticated: true, accountEmail: "user@example.com", message: nil)),
            paths: paths
        )
        let loginCoordinator = CodexLoginCoordinator(authService: authService, paths: paths)
        let viewModel = AuthViewModel(
            authService: authService,
            loginCoordinator: loginCoordinator,
            initialState: .default(),
            openURL: { _ in true }
        )

        await viewModel.performStartupCheckIfNeeded()

        #expect(viewModel.isAuthenticated)
        #expect(viewModel.authState.accountEmail == "user@example.com")
    }

    @Test
    func refreshStatusSurfacesUnauthenticatedState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = CodexAuthStore(paths: paths)
        let authService = CodexAuthService(
            store: store,
            runtime: AuthViewModelStubRuntime(loginStatus: .init(isAuthenticated: false, accountEmail: nil, message: "Not logged in")),
            paths: paths
        )
        let loginCoordinator = CodexLoginCoordinator(authService: authService, paths: paths)
        let viewModel = AuthViewModel(
            authService: authService,
            loginCoordinator: loginCoordinator,
            initialState: .default(),
            openURL: { _ in true }
        )

        await viewModel.refreshStatus()

        #expect(!viewModel.isAuthenticated)
        #expect(viewModel.authState.status == .unauthenticated)
        #expect(viewModel.statusTitle == "Get started with Codex")
    }
}

private struct AuthViewModelStubRuntime: CodexRuntime {
    var loginStatus: CodexLoginStatusResult

    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: "stub-thread", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func checkLoginStatus(codexHome: String) throws -> CodexLoginStatusResult {
        loginStatus
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
