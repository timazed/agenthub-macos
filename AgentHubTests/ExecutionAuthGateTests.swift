import Foundation
import Testing
@testable import AgentHub

@MainActor
struct ExecutionAuthGateTests {
    @Test
    func chatSessionServiceBlocksWhenUnauthenticated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        try paths.prepare()
        try createDefaultPersona(at: paths)

        let authManager = FailingAuthManager()
        let service = ChatSessionService(
            sessionStore: AssistantSessionStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            runtime: UnauthenticatedRuntime(),
            paths: paths,
            runtimeConfigStore: AppRuntimeConfigStore(paths: paths),
            authManager: authManager
        )

        await #expect(throws: AuthManagerError.self) {
            try await service.sendUserMessage("hello")
        }
    }

    @Test
    func taskRunMarksTaskErrorWhenUnauthenticated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        try paths.prepare()
        try createDefaultPersona(at: paths)

        let taskStore = try TaskStore(paths: paths)
        let task = TaskRecord(
            id: UUID(),
            title: "Blocked task",
            instructions: "Do something",
            scheduleType: .manual,
            scheduleValue: "",
            state: .scheduled,
            codexThreadId: nil,
            personaId: "default",
            runtimeMode: .chatOnly,
            repoPath: nil,
            createdAt: .now,
            updatedAt: .now,
            lastRun: nil,
            nextRun: nil,
            lastError: nil
        )
        try taskStore.upsert(task)

        let configStore = AppRuntimeConfigStore(paths: paths)
        let orchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: TaskRunStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: configStore,
            authManager: FailingAuthManager(),
            runtimeFactory: { UnauthenticatedRuntime() }
        )

        await #expect(throws: AuthManagerError.self) {
            try await orchestrator.runTask(taskId: task.id)
        }

        let updated = try taskStore.find(taskId: task.id)
        #expect(updated?.state == .error)
        #expect(updated?.lastError == "Not logged in")
    }

    private func createDefaultPersona(at paths: AppPaths) throws {
        let directory = paths.personasDirectory.appendingPathComponent("default", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "You are a test persona.\n".write(
            to: directory.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct FailingAuthManager: AuthManaging {
    func loadCachedState() throws -> AuthState {
        AuthState(provider: .codex, status: .unauthenticated, accountLabel: nil, lastValidatedAt: nil, failureReason: "Not logged in", updatedAt: Date())
    }

    func refreshStatus() throws -> AuthState {
        try loadCachedState()
    }

    func requireAuthenticated() throws {
        throw AuthManagerError.unauthenticated("Not logged in")
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        throw AuthManagerError.unauthenticated("Not logged in")
    }

    func waitForLoginCompletion() async throws -> AuthState {
        try loadCachedState()
    }

    func cancelLogin() {}
}

private struct UnauthenticatedRuntime: AssistantRuntime {
    func startNewThread(prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: nil, exitCode: 1, stdout: "", stderr: "Not logged in")
    }

    func resumeThread(threadId: String, prompt: String, config: AssistantLaunchConfig) async throws -> AssistantExecutionResult {
        AssistantExecutionResult(threadId: threadId, exitCode: 1, stdout: "", stderr: "Not logged in")
    }

    func checkLoginStatus(codexHome: String) throws -> AssistantLoginStatusResult {
        AssistantLoginStatusResult(isAuthenticated: false, accountEmail: nil, message: "Not logged in")
    }

    func streamEvents() -> AsyncStream<AssistantEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
