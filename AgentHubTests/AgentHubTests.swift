//
//  AgentHubTests.swift
//  AgentHubTests
//
//  Created by Timothy Zelinsky on 4/3/2026.
//

import Foundation
import Testing
@testable import AgentHub

struct AgentHubTests {
    @Test
    func taskStoreRoundTripsThreadBackedTasks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let store = try TaskStore(paths: paths)

        let task = TaskRecord(
            id: UUID(),
            title: "Bondi rentals",
            instructions: "Check for rentals under $900",
            scheduleType: .dailyAtHHMM,
            scheduleValue: "08:00",
            state: .scheduled,
            provider: .codex,
            providerThreadID: "thread-123",
            personaId: "default",
            runtimeMode: .chatOnly,
            repoPath: nil,
            createdAt: .now,
            updatedAt: .now,
            lastRun: nil,
            nextRun: .now,
            lastError: nil
        )

        try store.upsert(task)
        let loaded = try store.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.providerThreadID == "thread-123")
        #expect(loaded.first?.title == "Bondi rentals")
    }

    @Test
    func computeNextRunSupportsManualAndInterval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let runtimeConfigStore = AppRuntimeConfigStore(paths: paths)
        let authStore = AuthStore(paths: paths)
        let providerRegistry = ProviderRegistry(
            paths: paths,
            authStore: authStore,
            registrations: [dummyProviderRegistration]
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

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manual = orchestrator.computeNextRun(after: now, scheduleType: .manual, scheduleValue: "")
        let interval = orchestrator.computeNextRun(after: now, scheduleType: .intervalMinutes, scheduleValue: "30")

        #expect(manual == nil)
        #expect(interval != nil)
        #expect(abs(interval!.timeIntervalSince(now) - 1800) < 1)
    }

    @Test
    func providerRegistryUsesOnlyRegisteredProvider() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let registry = ProviderRegistry(
            paths: paths,
            authStore: AuthStore(paths: paths),
            registrations: [dummyProviderRegistration]
        )

        #expect(registry.currentProvider() == .codex)
    }

    @Test
    func providerRegistryCanUseNonCodexProviderWhenThatIsAllThatIsRegistered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHubTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AppPaths(root: root)
        let registry = ProviderRegistry(
            paths: paths,
            authStore: AuthStore(paths: paths),
            registrations: [claudeOnlyProviderRegistration]
        )

        #expect(registry.currentProvider() == .claude)
    }

}

private struct DummyRuntime: CodexRuntime {
    func startNewThread(prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: "dummy", exitCode: 0, stdout: "", stderr: "")
    }

    func resumeThread(threadId: String, prompt: String, config: CodexLaunchConfig) async throws -> CodexExecutionResult {
        CodexExecutionResult(threadId: threadId, exitCode: 0, stdout: "", stderr: "")
    }

    func checkLoginStatus(codexHome: String) throws -> CodexLoginStatusResult {
        CodexLoginStatusResult(isAuthenticated: true, accountEmail: nil, message: nil)
    }

    func streamEvents() -> AsyncStream<CodexEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRun() throws {}
}

private let dummyProviderRegistration = ProviderRegistration(
    provider: .codex,
    capabilities: .available(authMethods: [.browser]),
    makeRuntime: { DummyRuntime() },
    makeAuthProviderClient: { runtime, paths in
        CodexAuthProviderClient(runtime: runtime, paths: paths)
    }
)

private let claudeOnlyProviderRegistration = ProviderRegistration(
    provider: .claude,
    capabilities: .available(authMethods: [.externalSetup], supportsChat: true, supportsScheduledTasks: false),
    makeRuntime: { DummyRuntime() },
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
