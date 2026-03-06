import Foundation
import Testing
@testable import AgentHub

struct CodexAuthServiceTests {
    @Test
    func refreshStatusPersistsAuthenticatedState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = CodexAuthStore(paths: paths)
        let service = CodexAuthService(
            store: store,
            runtime: StubCodexRuntime(loginStatus: .init(isAuthenticated: true, accountEmail: "user@example.com", message: "Logged in as user@example.com")),
            paths: paths
        )

        let state = try service.refreshStatus()

        #expect(state.status == .authenticated)
        #expect(state.accountEmail == "user@example.com")
        #expect(state.lastValidatedAt != nil)
    }

    @Test
    func requireAuthenticatedThrowsForLoggedOutState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = CodexAuthStore(paths: paths)
        let service = CodexAuthService(
            store: store,
            runtime: StubCodexRuntime(loginStatus: .init(isAuthenticated: false, accountEmail: nil, message: "Not logged in")),
            paths: paths
        )

        #expect(throws: CodexAuthServiceError.self) {
            try service.requireAuthenticated()
        }

        let cached = try store.loadOrCreateDefault()
        #expect(cached.status == .unauthenticated)
        #expect(cached.failureReason == "Not logged in")
    }
}

private struct StubCodexRuntime: CodexRuntime {
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
