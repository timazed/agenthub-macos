import Foundation

struct UnsupportedAssistantRuntime: AssistantRuntime {
    let provider: AuthProvider
    let message: String

    func startNewThread(prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        throw AssistantRuntimeError.launchFailed(message)
    }

    func resumeThread(threadId: String, prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        throw AssistantRuntimeError.launchFailed(message)
    }

    func checkLoginStatus(codexHome: String) throws -> AssistantLoginStatusResult {
        AssistantLoginStatusResult(
            isAuthenticated: false,
            accountEmail: nil,
            message: message
        )
    }

    func streamEvents() -> AsyncStream<AssistantEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
