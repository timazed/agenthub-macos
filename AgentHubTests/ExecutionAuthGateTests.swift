import Foundation
import Testing
@testable import AgentHub

struct ExecutionAuthGateTests {
    @Test
    func chatSessionServiceBlocksWhenUnauthenticated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        try paths.prepare()
        try createDefaultPersona(at: paths)

        let runtime = UnauthenticatedRuntime()
        let authService = CodexAuthService(
            store: CodexAuthStore(paths: paths),
            runtime: runtime,
            paths: paths
        )
        let service = ChatSessionService(
            sessionStore: AssistantSessionStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            runtime: runtime,
            paths: paths,
            runtimeConfigStore: AppRuntimeConfigStore(paths: paths),
            authService: authService
        )

        await #expect(throws: CodexAuthServiceError.self) {
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

        let authService = CodexAuthService(
            store: CodexAuthStore(paths: paths),
            runtime: UnauthenticatedRuntime(),
            paths: paths
        )
        let orchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: TaskRunStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: AppRuntimeConfigStore(paths: paths),
            authService: authService,
            runtimeFactory: { UnauthenticatedRuntime() }
        )

        await #expect(throws: CodexAuthServiceError.self) {
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

private struct UnauthenticatedRuntime: CodexRuntime {
    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: nil, exitCode: 1, stdout: "", stderr: "Not logged in")
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: threadId, exitCode: 1, stdout: "", stderr: "Not logged in")
    }

    func checkLoginStatus(codexHome: String) throws -> CodexLoginStatusResult {
        CodexLoginStatusResult(isAuthenticated: false, accountEmail: nil, message: "Not logged in")
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
