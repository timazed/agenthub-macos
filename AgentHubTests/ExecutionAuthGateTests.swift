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
        let configStore = AppRuntimeConfigStore(paths: paths)
        let authStore = AuthStore(paths: paths)
        let service = ChatSessionService(
            sessionStore: AssistantSessionStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            paths: paths,
            runtimeConfigStore: configStore,
            providerRegistry: ProviderRegistry(
                paths: paths,
                runtimeConfigStore: configStore,
                authStore: authStore,
                registrations: [makeUnauthenticatedProviderRegistration(runtime: runtime)]
            )
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
            provider: .codex,
            providerThreadID: nil,
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
        let authStore = AuthStore(paths: paths)
        let orchestrator = TaskOrchestrator(
            taskStore: taskStore,
            taskRunStore: TaskRunStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: configStore,
            providerRegistry: ProviderRegistry(
                paths: paths,
                runtimeConfigStore: configStore,
                authStore: authStore,
                registrations: [makeUnauthenticatedProviderRegistration(runtime: UnauthenticatedRuntime())]
            )
        )

        await #expect(throws: AuthManagerError.self) {
            try await orchestrator.runTask(taskId: task.id)
        }

        let updated = try taskStore.find(taskId: task.id)
        #expect(updated?.state == .error)
        #expect(updated?.lastError == "Not logged in")
    }

    @Test
    func createTaskFailsWhenProviderDoesNotSupportTasks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        try paths.prepare()

        let runtimeConfigStore = AppRuntimeConfigStore(paths: paths)
        var config = try runtimeConfigStore.loadOrCreateDefault()
        config.defaultProvider = .claude
        try runtimeConfigStore.save(config)

        let providerRegistry = ProviderRegistry(
            paths: paths,
            runtimeConfigStore: runtimeConfigStore,
            authStore: AuthStore(paths: paths),
            registrations: [claudeChatOnlyProviderRegistration]
        )

        let orchestrator = TaskOrchestrator(
            taskStore: try TaskStore(paths: paths),
            taskRunStore: TaskRunStore(paths: paths),
            activityLogStore: ActivityLogStore(paths: paths),
            personaManager: PersonaManager(paths: paths),
            workspaceManager: WorkspaceManager(),
            paths: paths,
            runtimeConfigStore: runtimeConfigStore,
            providerRegistry: providerRegistry
        )

        await #expect(throws: NSError.self) {
            try await orchestrator.createTask(
                from: TaskProposal(
                    id: UUID(),
                    title: "Claude task",
                    instructions: "Do something",
                    scheduleType: .manual,
                    scheduleValue: "",
                    runtimeMode: .chatOnly,
                    repoPath: nil,
                    runNow: false
                )
            )
        }
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
    var currentProvider: AuthProvider { .codex }
    var availableProviders: [AuthProvider] { [.codex] }
    var capabilities: ProviderCapabilities { .available(authMethods: [.browser]) }

    func loadCachedState() throws -> AuthState {
        AuthState(provider: .codex, status: .unauthenticated, accountLabel: nil, lastValidatedAt: nil, failureReason: "Not logged in", updatedAt: Date())
    }

    func refreshStatus() throws -> AuthState {
        try loadCachedState()
    }

    func requireAuthenticated() throws {
        throw AuthManagerError.unauthenticated("Not logged in")
    }

    func selectProvider(_ provider: AuthProvider) throws -> AuthState {
        try loadCachedState()
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        throw AuthManagerError.unauthenticated("Not logged in")
    }

    func waitForLoginCompletion() async throws -> AuthState {
        try loadCachedState()
    }

    func cancelLogin() {}
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

private struct UnauthenticatedProviderClient: AuthProviderClient {
    let provider: AuthProvider = .codex
    let capabilities = ProviderCapabilities.available(authMethods: [.browser])

    func refreshStatus() throws -> AuthState {
        AuthState(provider: .codex, status: .unauthenticated, accountLabel: nil, lastValidatedAt: nil, failureReason: "Not logged in", updatedAt: Date())
    }

    func startLogin() async throws -> AuthLoginChallenge? {
        throw AuthManagerError.unauthenticated("Not logged in")
    }

    func waitForLoginCompletion() async throws -> AuthState {
        try refreshStatus()
    }

    func cancelLogin() {}
}

private func makeUnauthenticatedProviderRegistration(runtime: AssistantRuntime) -> ProviderRegistration {
    ProviderRegistration(
        provider: .codex,
        capabilities: .available(authMethods: [.browser]),
        makeRuntime: { runtime },
        makeAuthProviderClient: { _, _ in
            UnauthenticatedProviderClient()
        }
    )
}

private let claudeChatOnlyProviderRegistration = ProviderRegistration(
    provider: .claude,
    capabilities: .available(authMethods: [.externalSetup], supportsChat: true, supportsScheduledTasks: false),
    makeRuntime: { ClaudeChatOnlyRuntime() },
    makeAuthProviderClient: { _, _ in
        ClaudeProviderClientStub()
    }
)

private struct ClaudeProviderClientStub: AuthProviderClient {
    let provider: AuthProvider = .claude
    let capabilities = ProviderCapabilities.available(authMethods: [.externalSetup], supportsChat: true, supportsScheduledTasks: false)

    func refreshStatus() throws -> AuthState {
        AuthState(provider: .claude, status: .authenticated, accountLabel: "claude@example.com", lastValidatedAt: Date(), failureReason: nil, updatedAt: Date())
    }

    func startLogin() async throws -> AuthLoginChallenge? { nil }
    func waitForLoginCompletion() async throws -> AuthState { try refreshStatus() }
    func cancelLogin() {}
}

private struct ClaudeChatOnlyRuntime: CodexRuntime {
    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: "claude-thread", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func checkLoginStatus(codexHome: String) throws -> CodexLoginStatusResult {
        CodexLoginStatusResult(isAuthenticated: true, accountEmail: "claude@example.com", message: nil)
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}
