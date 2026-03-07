import Foundation

struct UnsupportedAssistantRuntime: AssistantRuntime {
    let provider: AuthProvider
    let message: String

    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        throw AssistantRuntimeError.launchFailed(message)
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        throw AssistantRuntimeError.launchFailed(message)
    }

    func checkLoginStatus(codexHome: String) throws -> CodexLoginStatusResult {
        CodexLoginStatusResult(
            isAuthenticated: false,
            accountEmail: nil,
            message: message
        )
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
