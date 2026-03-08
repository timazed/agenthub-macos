import Foundation
import Testing
@testable import AgentHub

@MainActor
struct CodexAuthProviderClientTests {
    @Test
    func refreshStatusMapsRuntimeStateToAuthState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let client = CodexAuthProviderClient(
            runtime: StubProviderRuntime(
                loginStatus: AssistantLoginStatusResult(
                    isAuthenticated: true,
                    accountEmail: "user@example.com",
                    message: "Logged in as user@example.com"
                )
            ),
            paths: AppPaths(root: root)
        )

        let state = try client.refreshStatus()

        #expect(state.provider == .codex)
        #expect(state.status == .authenticated)
        #expect(state.accountLabel == "user@example.com")
    }
}

private struct StubProviderRuntime: AssistantRuntime {
    var loginStatus: AssistantLoginStatusResult

    func startNewThread(prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: "stub-thread", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func checkLoginStatus(codexHome: String) throws -> AssistantLoginStatusResult {
        loginStatus
    }

    func streamEvents() -> AsyncStream<AssistantEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
